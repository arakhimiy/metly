// Connection writes: the LWW upsert, the contact list a write stores (including legacy clients),
// and merging a second record for the same remote user into its existing twin.
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import type { Connection, Prisma } from '../../generated/prisma/client';
import type { ApplyResult } from '../changes';
import { connectionContactData, connectionContacts, connectionLegacyInput, contactsToLegacy, legacyToContacts, mergeContacts } from '../contacts';
import { connectionToWire, contextToJson } from '../mappers';
import type { ConnectionIn, ContactEntry } from '../wire';
import { lww, type WriteContext } from '../write-context';
import { RecordCore } from './record-core';

const STRING_FIELDS = ['fullName', 'jobTitle', 'company', 'note'] as const;

@Injectable()
export class ConnectionWriter {
  constructor(private readonly core: RecordCore) {}

  /**
   * The list a connection write stores: `contacts` as sent, or — from an app before the contact list —
   * `stored` with what the legacy fields express rebuilt from them. Without `phoneLabel` /
   * `additionalPhones` (an app before labelled phones) the stored ones are kept.
   */
  incomingConnectionContacts(incoming: ConnectionIn, stored: ContactEntry[]): ContactEntry[] {
    if (incoming.contacts) return incoming.contacts;
    const storedLegacy = contactsToLegacy(stored);
    const input = connectionLegacyInput({ ...incoming, phoneLabel: undefined, additionalPhones: undefined });
    return legacyToContacts(
      {
        primary: input.primary,
        phoneLabel: incoming.phoneLabel ?? storedLegacy.phoneLabel,
        additionalPhones: incoming.additionalPhones ?? storedLegacy.additionalPhones,
      },
      stored,
    );
  }

  connectionData(incoming: ConnectionIn, contacts: ContactEntry[]) {
    return {
      remoteUserId: incoming.remoteUserId,
      fullName: incoming.fullName,
      jobTitle: incoming.jobTitle,
      company: incoming.company,
      ...connectionContactData(contacts),
      theirCard: (incoming.theirCard ?? undefined) as Prisma.InputJsonValue | undefined,
      mySharedCardId: incoming.mySharedCardId,
      source: incoming.source,
      context: contextToJson(incoming.context) as Prisma.InputJsonValue,
      previousMeetings: incoming.previousMeetings.map(contextToJson) as Prisma.InputJsonValue,
      eventId: incoming.eventId,
      note: incoming.note,
      tags: incoming.tags as Prisma.InputJsonValue,
      isMerged: incoming.isMerged,
      isPendingMerge: incoming.isPendingMerge,
      isBlocked: incoming.isBlocked,
      updatedAt: incoming.updatedAt,
    };
  }

  async upsertConnection(ctx: WriteContext, incoming: ConnectionIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.connection.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.core.emitConnection(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;

    // One live connection per (owner, remoteUserId): a second record for the same Nameshake user merges
    // into the existing one and the pushed id is tombstoned (README § Uniqueness).
    if (!live && incoming.remoteUserId) {
      const twin = await tx.connection.findFirst({
        where: { userId, remoteUserId: incoming.remoteUserId, deletedAt: null, NOT: { id: incoming.id } },
        orderBy: { createdAt: 'asc' },
      });
      if (twin) {
        await this.mergeIntoTwin(ctx, incoming, existing, twin);
        return { status: 'applied' };
      }
    }

    const seq = await this.core.bump(ctx);
    const stored = live ? connectionContacts(live) : [];
    const data = {
      ...this.connectionData(incoming, this.incomingConnectionContacts(incoming, stored)),
      theirCard: (incoming.theirCard ?? null) as Prisma.InputJsonValue,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.connection.update({ where: { id: existing.id }, data })
      : await tx.connection.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });
    this.core.emitConnection(ctx, row);
    return { status: 'applied' };
  }

  private async mergeIntoTwin(ctx: WriteContext, incoming: ConnectionIn, existing: Connection | null, twin: Connection) {
    const { tx, userId } = ctx;
    const incomingWins = incoming.updatedAt >= twin.updatedAt;
    const twinWire = connectionToWire(twin) as Record<string, unknown>;
    const merged: Record<string, unknown> = {};
    for (const field of STRING_FIELDS) {
      const mine = incomingWins ? incoming[field] : (twinWire[field] as string);
      const other = incomingWins ? (twinWire[field] as string) : incoming[field];
      merged[field] = mine !== '' ? mine : other;
    }
    // Contacts: the newer record's list, then the other's entries not in it yet (a record that didn't
    // send a list — an older client — counts as its legacy fields).
    const storedIncoming = existing && !existing.deletedAt ? connectionContacts(existing) : [];
    const incomingContacts = this.incomingConnectionContacts(incoming, storedIncoming);
    const twinContacts = connectionContacts(twin);
    const [winner, loser] = incomingWins ? [incomingContacts, twinContacts] : [twinContacts, incomingContacts];
    const contacts = mergeContacts(winner, loser).contacts;
    const base = incomingWins ? this.connectionData(incoming, contacts) : null;
    const theirCard = (incomingWins ? (incoming.theirCard ?? twin.theirCard) : (twin.theirCard ?? incoming.theirCard)) ?? null;
    const survivor = await tx.connection.update({
      where: { id: twin.id },
      data: {
        ...(base ?? {}),
        ...merged,
        ...connectionContactData(contacts),
        remoteUserId: twin.remoteUserId,
        theirCard: theirCard as Prisma.InputJsonValue,
        createdAt: twin.createdAt < incoming.createdAt ? twin.createdAt : incoming.createdAt,
        updatedAt: incomingWins ? incoming.updatedAt : twin.updatedAt,
        seq: await this.core.bump(ctx),
      },
    });

    // The pushed id becomes a tombstone (kept for sync like any other).
    const deletedAt = incoming.updatedAt;
    const tombstoneData = {
      ...this.connectionData(incoming, incomingContacts),
      theirCard: undefined,
      note: '',
      deletedAt,
      seq: await this.core.bump(ctx),
    };
    if (existing) await tx.connection.update({ where: { id: existing.id }, data: tombstoneData });
    else await tx.connection.create({ data: { ...tombstoneData, id: incoming.id, userId, createdAt: incoming.createdAt } });
    await tx.connectionAlias.upsert({
      where: { aliasId: incoming.id },
      create: { aliasId: incoming.id, userId, survivorId: twin.id },
      update: { survivorId: twin.id },
    });

    // Follow-ups of the duplicate belong to the survivor — never cascade-deleted.
    const children = await tx.followUp.findMany({ where: { userId, connectionId: incoming.id, deletedAt: null } });
    for (const child of children) {
      const row = await tx.followUp.update({ where: { id: child.id }, data: { connectionId: twin.id, seq: await this.core.bump(ctx) } });
      this.core.emitFollowUp(ctx, row);
    }
    this.core.emitConnection(ctx, survivor);
    ctx.out.tombstone('connection', incoming.id, deletedAt);
  }
}
