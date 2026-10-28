import { Inject, Injectable } from '@nestjs/common';
import { ApiError } from '../common/api-error';
import { randomToken } from '../common/crypto';
import { DomainEvents } from '../common/domain-events';
import { ENV, type Env } from '../config/env';
import type { Card, Connection, Event, FollowUp, Prisma, Profile } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { EntitlementsService, type PlanLimits } from '../subscriptions/entitlements.service';
import { type ApplyResult, ChangeSet } from './changes';
import {
  cardToWire,
  connectionToWire,
  contextToJson,
  eventToWire,
  followUpToWire,
  profileToWire,
} from './mappers';
import {
  connectionContactData,
  connectionContacts,
  connectionLegacyInput,
  contactsToLegacy,
  legacyToContacts,
  mergeContacts,
  profileContactData,
  profileContacts,
  profileLegacyInput,
} from './contacts';
import { slugCandidate, slugStem } from './slug';
import {
  type CardDesign,
  type CardIn,
  type ConnectionIn,
  type ContactEntry,
  type EventIn,
  type FollowUpIn,
  PRO_PALETTES,
  PRO_TEMPLATES,
  type ProfileIn,
  type SyncRecordType,
  type TombstoneIn,
} from './wire';

/** Side effects collected during a write transaction, published after it commits. */
export class Effects {
  readonly usersChanged = new Set<string>();
  readonly cardsContentChanged = new Set<string>();
}

/** One write transaction for one user: where canonical records and side effects are collected. */
export class WriteContext {
  readonly effects = new Effects();
  private linksPausedCache: boolean | undefined;
  private plan: { pro: boolean; limits: PlanLimits } | undefined;

  constructor(
    readonly tx: Tx,
    readonly userId: string,
    readonly out: ChangeSet = new ChangeSet(),
  ) {}

  async linksPaused(): Promise<boolean> {
    if (this.linksPausedCache === undefined) {
      const profile = await this.tx.profile.findUnique({ where: { userId: this.userId }, select: { linksPaused: true, deletedAt: true } });
      this.linksPausedCache = profile && !profile.deletedAt ? profile.linksPaused : false;
    }
    return this.linksPausedCache;
  }

  setLinksPaused(value: boolean) {
    this.linksPausedCache = value;
  }

  async planFor(entitlements: EntitlementsService) {
    this.plan ??= await entitlements.limits(this.userId, this.tx);
    return this.plan;
  }
}

type Verdict = 'apply' | 'staleTombstone' | 'staleLive';

/** README § Conflict resolution, for an incoming upsert with updatedAt = U. */
function lww(existing: { updatedAt: Date; deletedAt: Date | null } | null, updatedAt: Date): Verdict {
  if (!existing) return 'apply';
  if (existing.deletedAt) return existing.deletedAt >= updatedAt ? 'staleTombstone' : 'apply';
  return existing.updatedAt > updatedAt ? 'staleLive' : 'apply';
}

const STRING_FIELDS = ['fullName', 'jobTitle', 'company', 'note'] as const;

const designUsesPro = (design: CardDesign) => PRO_TEMPLATES.has(design.template) || PRO_PALETTES.has(design.palette);
const sameJson = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

@Injectable()
export class RecordsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly entitlements: EntitlementsService,
    private readonly events: DomainEvents,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Runs `fn` in a transaction and publishes its side effects once it committed. */
  async write<T>(userId: string, fn: (ctx: WriteContext) => Promise<T>, originDeviceId?: string | null): Promise<{ result: T; out: ChangeSet }> {
    let ctx!: WriteContext;
    const result = await this.prisma.write(async (tx) => {
      ctx = new WriteContext(tx, userId);
      return fn(ctx);
    });
    this.publish(ctx.effects, originDeviceId);
    return { result, out: ctx.out };
  }

  publish(effects: Effects, originDeviceId?: string | null) {
    for (const userId of effects.usersChanged) this.events.emit('user.changed', { userId, originDeviceId });
    if (effects.cardsContentChanged.size > 0) {
      this.events.emit('cards.content.changed', { cardIds: [...effects.cardsContentChanged] });
    }
  }

  private async bump(ctx: WriteContext, userId = ctx.userId): Promise<bigint> {
    ctx.effects.usersChanged.add(userId);
    return this.prisma.nextSeq(ctx.tx, userId);
  }

  // ───────────────────────────── Emit canonical rows ─────────────────────────────

  emitProfile(ctx: WriteContext, row: Profile) {
    if (row.deletedAt) ctx.out.tombstone('profile', row.id, row.deletedAt);
    else ctx.out.record('profile', this.profileWire(row, ctx));
  }

  private profileWire(row: Profile, _ctx: WriteContext) {
    return profileToWire(row);
  }

  async emitCard(ctx: WriteContext, row: Card) {
    if (row.deletedAt) ctx.out.tombstone('card', row.id, row.deletedAt);
    else ctx.out.record('card', cardToWire(row, { webBaseUrl: this.env.WEB_BASE_URL, linksPaused: await ctx.linksPaused() }));
  }

  emitEvent(ctx: WriteContext, row: Event) {
    if (row.deletedAt) ctx.out.tombstone('event', row.id, row.deletedAt);
    else ctx.out.record('event', eventToWire(row));
  }

  emitConnection(ctx: WriteContext, row: Connection) {
    if (row.deletedAt) ctx.out.tombstone('connection', row.id, row.deletedAt);
    else ctx.out.record('connection', connectionToWire(row));
  }

  emitFollowUp(ctx: WriteContext, row: FollowUp) {
    if (row.deletedAt) ctx.out.tombstone('followUp', row.id, row.deletedAt);
    else ctx.out.record('followUp', followUpToWire(row));
  }

  // ───────────────────────────── Profile ─────────────────────────────

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
      this.emitProfile(ctx, existing);
      return { status: 'stale' };
    }
    const user = await tx.user.findUniqueOrThrow({ where: { id: userId }, select: { telegramChatId: true } });
    const notificationPrefs = { ...incoming.notificationPrefs, telegramLinked: user.telegramChatId !== null };
    const seq = await this.bump(ctx);
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
      !sameJson(profileContacts(existing), row.contacts);
    ctx.setLinksPaused(row.linksPaused);
    if (pauseChanged || publicChanged) await this.touchAllCards(ctx, { republish: true, bumpSeq: pauseChanged });
    this.emitProfile(ctx, row);
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

  /**
   * Cards derive isPaused and their public content from the profile: bump their seq so devices pull
   * the new isPaused, and their contentUpdatedAt so pages and Wallet passes refresh.
   */
  async touchAllCards(ctx: WriteContext, opts: { republish: boolean; bumpSeq: boolean }) {
    const cards = await ctx.tx.card.findMany({ where: { userId: ctx.userId, deletedAt: null } });
    for (const card of cards) {
      const data: Prisma.CardUpdateInput = {};
      if (opts.bumpSeq) data.seq = await this.bump(ctx);
      if (opts.republish) {
        data.contentUpdatedAt = new Date();
        ctx.effects.cardsContentChanged.add(card.id);
      }
      const row = await ctx.tx.card.update({ where: { id: card.id }, data });
      if (opts.bumpSeq) await this.emitCard(ctx, row);
    }
  }

  // ───────────────────────────── Cards ─────────────────────────────

  async upsertCard(ctx: WriteContext, incoming: CardIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.card.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      await this.emitCard(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);

    if (!live && plan.limits.maxCards !== null) {
      const count = await tx.card.count({ where: { userId, deletedAt: null, NOT: { id: incoming.id } } });
      if (count >= plan.limits.maxCards) {
        return { status: 'rejected', error: ApiError.planLimit('cards', `The Free plan includes ${plan.limits.maxCards} cards.`) };
      }
    }
    const designChanged = !live || !sameJson(live.design, incoming.design);
    if (!plan.pro && designChanged && designUsesPro(incoming.design)) {
      return { status: 'rejected', error: ApiError.proRequired('Editorial and the Ocean and Ember palettes need Tanishly Pro.') };
    }
    if (live?.isReadOnly && (designChanged || live.name !== incoming.name)) {
      return { status: 'rejected', error: ApiError.proRequired('This card is read-only on the Free plan.') };
    }

    const seq = await this.bump(ctx);
    const contentChanged = !live || designChanged || live.name !== incoming.name;
    const data = {
      name: incoming.name,
      sortOrder: incoming.sortOrder,
      design: incoming.design as unknown as Prisma.InputJsonValue,
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
      ...(contentChanged ? { contentUpdatedAt: new Date() } : {}),
    };
    let row: Card;
    if (existing) {
      row = await tx.card.update({ where: { id: existing.id }, data });
      if (!row.slug) row = await this.assignSlug(ctx, row);
    } else {
      row = await tx.card.create({
        data: {
          ...data,
          id: incoming.id,
          userId,
          createdAt: incoming.createdAt,
          passAuthToken: randomToken(24),
          contentUpdatedAt: new Date(),
        },
      });
      row = await this.assignSlug(ctx, row);
    }
    if (contentChanged) ctx.effects.cardsContentChanged.add(row.id);
    await this.emitCard(ctx, row);
    return { status: 'applied' };
  }

  /** First accepted write: `{firstname}-{4}`, globally unique and never reused. */
  private async assignSlug(ctx: WriteContext, card: Card): Promise<Card> {
    const profile = await ctx.tx.profile.findUnique({ where: { userId: ctx.userId }, select: { fullName: true } });
    const stem = slugStem(profile?.fullName ?? '');
    for (let attempt = 0; attempt < 20; attempt++) {
      const slug = slugCandidate(stem);
      // ON CONFLICT keeps the transaction usable when the candidate is taken.
      const inserted = await ctx.tx.$executeRaw`INSERT INTO slugs (slug, card_id) VALUES (${slug}, ${card.id}::uuid) ON CONFLICT DO NOTHING`;
      if (inserted === 1) return ctx.tx.card.update({ where: { id: card.id }, data: { slug } });
    }
    throw new Error('Could not allocate a unique slug');
  }

  // ───────────────────────────── Events ─────────────────────────────

  async upsertEvent(ctx: WriteContext, incoming: EventIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.event.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.emitEvent(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);
    if (incoming.status === 'active' && live?.status !== 'active' && plan.limits.maxActiveEvents !== null) {
      const active = await tx.event.count({ where: { userId, deletedAt: null, status: 'active', NOT: { id: incoming.id } } });
      if (active >= plan.limits.maxActiveEvents) {
        return {
          status: 'rejected',
          error: ApiError.planLimit('activeEvents', `The Free plan includes ${plan.limits.maxActiveEvents} active event.`),
        };
      }
    }
    const seq = await this.bump(ctx);
    const data = {
      name: incoming.name,
      place: incoming.place,
      city: incoming.city,
      startDate: incoming.startDate,
      endDate: incoming.endDate,
      cardId: incoming.cardId,
      status: incoming.status,
      calendarEventIdentifier: incoming.calendarEventIdentifier,
      endedAt: incoming.status === 'ended' ? (incoming.endedAt ?? new Date()) : null,
      // Resuming re-arms the end-of-event summary.
      ...(incoming.status === 'active' ? { summarySentAt: null } : {}),
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.event.update({ where: { id: existing.id }, data })
      : await tx.event.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });

    if (live && live.name !== row.name) await this.cascadeEventRename(ctx, row);
    this.emitEvent(ctx, row);
    return { status: 'applied' };
  }

  /** Rename → `context.eventName` of tagged connections; their updatedAt = max(own, event's). */
  private async cascadeEventRename(ctx: WriteContext, event: Event) {
    const tagged = await ctx.tx.connection.findMany({ where: { userId: ctx.userId, eventId: event.id, deletedAt: null } });
    for (const connection of tagged) {
      const context = { ...(connection.context as Record<string, unknown>), eventName: event.name };
      const row = await ctx.tx.connection.update({
        where: { id: connection.id },
        data: {
          context,
          updatedAt: connection.updatedAt > event.updatedAt ? connection.updatedAt : event.updatedAt,
          seq: await this.bump(ctx),
        },
      });
      this.emitConnection(ctx, row);
    }
  }

  // ───────────────────────────── Connections ─────────────────────────────

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
      this.emitConnection(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;

    // One live connection per (owner, remoteUserId): a second record for the same Tanishly user merges
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

    const seq = await this.bump(ctx);
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
    this.emitConnection(ctx, row);
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
        seq: await this.bump(ctx),
      },
    });

    // The pushed id becomes a tombstone (kept for sync like any other).
    const deletedAt = incoming.updatedAt;
    const tombstoneData = {
      ...this.connectionData(incoming, incomingContacts),
      theirCard: undefined,
      note: '',
      deletedAt,
      seq: await this.bump(ctx),
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
      const row = await tx.followUp.update({ where: { id: child.id }, data: { connectionId: twin.id, seq: await this.bump(ctx) } });
      this.emitFollowUp(ctx, row);
    }
    this.emitConnection(ctx, survivor);
    ctx.out.tombstone('connection', incoming.id, deletedAt);
  }

  // ───────────────────────────── Follow-ups ─────────────────────────────

  async upsertFollowUp(ctx: WriteContext, incoming: FollowUpIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.followUp.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.emitFollowUp(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);
    const opensNew = !incoming.isDone && (!live || live.isDone);
    if (opensNew && plan.limits.maxOpenFollowUps !== null) {
      const open = await tx.followUp.count({ where: { userId, deletedAt: null, isDone: false, NOT: { id: incoming.id } } });
      if (open >= plan.limits.maxOpenFollowUps) {
        return {
          status: 'rejected',
          error: ApiError.planLimit('openFollowUps', `The Free plan includes ${plan.limits.maxOpenFollowUps} active reminders.`),
        };
      }
    }
    const connectionId = incoming.connectionId ? await this.resolveConnectionAlias(ctx, incoming.connectionId) : null;
    const seq = await this.bump(ctx);
    const data = {
      connectionId,
      title: incoming.title,
      channel: incoming.channel,
      dueAt: incoming.dueAt,
      isDone: incoming.isDone,
      completedAt: incoming.isDone ? (incoming.completedAt ?? incoming.updatedAt) : null,
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.followUp.update({ where: { id: existing.id }, data })
      : await tx.followUp.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });
    this.emitFollowUp(ctx, row);
    return { status: 'applied' };
  }

  async resolveConnectionAlias(ctx: WriteContext, connectionId: string): Promise<string> {
    const alias = await ctx.tx.connectionAlias.findUnique({ where: { aliasId: connectionId } });
    return alias && alias.userId === ctx.userId ? alias.survivorId : connectionId;
  }

  /** Bulk create-or-update, all-or-nothing against the Free open follow-up limit. */
  async bulkUpsertFollowUps(ctx: WriteContext, items: FollowUpIn[]): Promise<void> {
    const plan = await ctx.planFor(this.entitlements);
    if (plan.limits.maxOpenFollowUps !== null) {
      const ids = items.map((i) => i.id);
      const stored = await ctx.tx.followUp.findMany({ where: { id: { in: ids } } });
      const storedById = new Map(stored.map((s) => [s.id, s]));
      const openOthers = await ctx.tx.followUp.count({
        where: { userId: ctx.userId, deletedAt: null, isDone: false, NOT: { id: { in: ids } } },
      });
      const openAfter = items.filter((i) => {
        const s = storedById.get(i.id);
        if (s && (s.deletedAt ? s.deletedAt >= i.updatedAt : s.updatedAt > i.updatedAt)) return !s.deletedAt && !s.isDone;
        return !i.isDone;
      }).length;
      if (openOthers + openAfter > plan.limits.maxOpenFollowUps) {
        throw ApiError.planLimit('openFollowUps', `The Free plan includes ${plan.limits.maxOpenFollowUps} active reminders.`);
      }
    }
    for (const item of items) {
      const result = await this.upsertFollowUp(ctx, item);
      if (result.status === 'rejected' && result.error) throw result.error;
    }
  }

  // ───────────────────────────── Tombstones ─────────────────────────────

  async applyTombstone(ctx: WriteContext, t: TombstoneIn): Promise<ApplyResult> {
    switch (t.type) {
      case 'profile':
        return this.tombstoneRow(ctx, t, 'profile');
      case 'card':
        return this.tombstoneRow(ctx, t, 'card');
      case 'event':
        return this.tombstoneRow(ctx, t, 'event');
      case 'connection':
        return this.tombstoneRow(ctx, t, 'connection');
      case 'followUp':
        return this.tombstoneRow(ctx, t, 'followUp');
      case 'connectRequest':
        // Requests change only through the connect endpoints.
        return { status: 'rejected', error: ApiError.badRequest('Connect requests cannot be deleted through sync.') };
    }
  }

  private async tombstoneRow(ctx: WriteContext, t: TombstoneIn, type: Exclude<SyncRecordType, 'connectRequest'>): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const delegate = this.delegate(tx, type);
    const existing = (await delegate.findUnique({ where: { id: t.id } })) as
      | { id: string; userId: string; updatedAt: Date; deletedAt: Date | null }
      | null;
    if (!existing) {
      // Never reached the server; nothing to delete, but confirm so the device can forget it.
      ctx.out.tombstone(type, t.id, t.deletedAt);
      return { status: 'applied' };
    }
    if (existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    if (existing.deletedAt) {
      ctx.out.tombstone(type, t.id, existing.deletedAt);
      return { status: 'applied' };
    }
    if (existing.updatedAt > t.deletedAt) {
      await this.emitAny(ctx, type, existing);
      return { status: 'stale' };
    }
    const seq = await this.bump(ctx);
    await delegate.update({ where: { id: t.id }, data: { deletedAt: t.deletedAt, seq } });
    ctx.out.tombstone(type, t.id, t.deletedAt);
    await this.cascadeDelete(ctx, type, t.id, t.deletedAt);
    return { status: 'applied' };
  }

  async cascadeDelete(ctx: WriteContext, type: SyncRecordType, id: string, deletedAt: Date) {
    const { tx, userId } = ctx;
    if (type === 'connection') {
      const children = await tx.followUp.findMany({ where: { userId, connectionId: id, deletedAt: null } });
      for (const child of children) {
        await tx.followUp.update({ where: { id: child.id }, data: { deletedAt, seq: await this.bump(ctx) } });
        ctx.out.tombstone('followUp', child.id, deletedAt);
      }
    } else if (type === 'event') {
      const tagged = await tx.connection.findMany({ where: { userId, eventId: id, deletedAt: null } });
      for (const connection of tagged) {
        const row = await tx.connection.update({ where: { id: connection.id }, data: { eventId: null, seq: await this.bump(ctx) } });
        this.emitConnection(ctx, row);
      }
    } else if (type === 'card') {
      // The page, vCard and Wallet pass now say "deleted": that is a public content change.
      await tx.card.update({ where: { id }, data: { contentUpdatedAt: new Date() } });
      ctx.effects.cardsContentChanged.add(id);
    }
  }

  private async emitAny(ctx: WriteContext, type: Exclude<SyncRecordType, 'connectRequest'>, row: unknown) {
    switch (type) {
      case 'profile':
        return this.emitProfile(ctx, row as Profile);
      case 'card':
        return this.emitCard(ctx, row as Card);
      case 'event':
        return this.emitEvent(ctx, row as Event);
      case 'connection':
        return this.emitConnection(ctx, row as Connection);
      case 'followUp':
        return this.emitFollowUp(ctx, row as FollowUp);
    }
  }

  private delegate(tx: Tx, type: Exclude<SyncRecordType, 'connectRequest'>) {
    const delegates = {
      profile: tx.profile,
      card: tx.card,
      event: tx.event,
      connection: tx.connection,
      followUp: tx.followUp,
    } as const;
    return delegates[type] as unknown as {
      findUnique(args: { where: { id: string } }): Promise<unknown>;
      update(args: { where: { id: string }; data: Record<string, unknown> }): Promise<unknown>;
    };
  }
}
