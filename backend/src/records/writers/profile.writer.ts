// Profile writes: the one-per-user LWW upsert, the contact list a write stores (including legacy
// clients), and republishing the user's cards when the profile's public or pause state changes.
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import type { Prisma, Profile } from '../../generated/prisma/client';
import type { ApplyResult } from '../changes';
import { contactsToLegacy, legacyToContacts, profileContactData, profileContacts, profileLegacyInput } from '../contacts';
import type { ContactEntry, ProfileIn } from '../wire';
import { lww, sameJson, type WriteContext } from '../write-context';
import { CardWriter } from './card.writer';
import { RecordCore } from './record-core';

@Injectable()
export class ProfileWriter {
  constructor(
    private readonly core: RecordCore,
    private readonly cards: CardWriter,
  ) {}

  async upsertProfile(ctx: WriteContext, incoming: ProfileIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    // One profile per user, found by user — the stored id stays canonical.
    const existing = await tx.profile.findUnique({ where: { userId } });
    if (!existing) {
      const clash = await tx.profile.findUnique({ where: { id: incoming.id }, select: { userId: true } });
      if (clash) return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.core.emitProfile(ctx, existing);
      return { status: 'stale' };
    }
    const notificationPrefs = incoming.notificationPrefs;
    const seq = await this.core.bump(ctx);
    const data = {
      fullName: incoming.fullName,
      jobTitle: incoming.jobTitle,
      company: incoming.company,
      ...profileContactData(this.incomingProfileContacts(incoming, existing)),
      defaultCardId: incoming.defaultCardId,
      linksPaused: incoming.linksPaused,
      notificationPrefs: notificationPrefs as unknown as Prisma.InputJsonValue,
      privacySettings: incoming.privacySettings as unknown as Prisma.InputJsonValue,
      isSetupComplete: incoming.isSetupComplete,
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.profile.update({ where: { userId }, data })
      : await tx.profile.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });

    const pauseChanged = (existing?.deletedAt ? false : existing?.linksPaused ?? false) !== row.linksPaused;
    const publicChanged =
      !existing ||
      existing.fullName !== row.fullName ||
      existing.jobTitle !== row.jobTitle ||
      existing.company !== row.company ||
      !sameJson(profileContacts(existing), profileContacts(row));
    ctx.setLinksPaused(row.linksPaused);
    if (pauseChanged || publicChanged) await this.cards.touchAllCards(ctx, { republish: true, bumpSeq: pauseChanged });
    this.core.emitProfile(ctx, row);
    return { status: 'applied' };
  }

  /**
   * The list a profile write stores: `contacts` as sent, or — from an app before the contact list —
   * the stored list with what the legacy fields express rebuilt from them (CONTACTS.md § Legacy → list).
   * Without `phoneLabel`/`additionalPhones` (an app before labelled phones) the stored ones are kept.
   */
  private incomingProfileContacts(incoming: ProfileIn, existing: Profile | null): ContactEntry[] {
    if (incoming.contacts) return incoming.contacts;
    const stored = existing && !existing.deletedAt ? profileContacts(existing) : [];
    const storedLegacy = contactsToLegacy(stored);
    const input = profileLegacyInput({ contactFields: incoming.contactFields });
    return legacyToContacts(
      {
        primary: input.primary,
        phoneLabel: incoming.phoneLabel ?? storedLegacy.phoneLabel,
        additionalPhones: incoming.additionalPhones ?? storedLegacy.additionalPhones,
      },
      stored,
    );
  }
}
