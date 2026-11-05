import { randomUUID } from 'node:crypto';
import { Inject, Injectable, Logger } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { randomToken } from '../common/crypto';
import { decodeOffset, encodeOffset } from '../common/cursor';
import { iso, minutes } from '../common/time';
import { parse } from '../common/validate';
import { ENV, type Env } from '../config/env';
import type { Card, Connection, ConnectRequest, Prisma, Profile } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { PushService } from '../push/push.service';
import { RealtimeService } from '../realtime/realtime.service';
import { connectionToWire } from '../records/mappers';
import { Effects, RecordsService } from '../records/records.service';
import { cardContactsView, connectionContactData, connectionContacts, mergeContacts } from '../records/contacts';
import { pathUuid } from '../records/rest';
import { cardSnapshot, firstName } from '../records/snapshot';
import {
  type CardDesign,
  ConnectMethod,
  type ConnectionSource,
  nullableUuid,
  type PrivacySettings,
  uuid,
} from '../records/wire';
import { blockedAmong, blockedBetween } from './blocks';
import { ASYNC_LIFETIME_MS, ConnectRequestView, LIVE_LIFETIME_MS, LIVE_METHODS, type VisibleStatus, visibleStatus } from './connect-request.view';

export const SESSION_LIFETIME_MS = minutes(10);
export const MAX_PEER_TOKENS = 50;

const SOURCE_BY_METHOD: Record<ConnectMethod, ConnectionSource> = {
  nearby: 'nearby',
  tapPhones: 'tapPhones',
  scan: 'scanQR',
  deferred: 'deferredLink',
  emailLookup: 'connectRequest',
};

const SessionBody = z.object({ cardId: uuid, eventId: nullableUuid, method: ConnectMethod });

const present = (v: string | null | undefined) => v !== null && v !== undefined && v.trim().length > 0;

const SendBody = z
  .object({
    toToken: z.string().max(200).nullish(),
    toUserId: nullableUuid,
    toSlug: z.string().max(100).nullish(),
    cardId: uuid,
    method: ConnectMethod,
    eventId: nullableUuid,
    eventName: z.string().max(200).nullish(),
    place: z.string().max(200).nullish(),
  })
  .superRefine((b, ctx) => {
    const targets = [b.toToken, b.toUserId, b.toSlug].filter(present).length;
    if (targets !== 1) ctx.addIssue({ code: 'custom', path: ['toToken'], message: 'exactly one of toToken, toUserId, toSlug is required' });
  });
type SendBody = z.infer<typeof SendBody>;

const AcceptBody = z.object({ cardId: uuid });

const ListQuery = z.object({
  status: z.enum(['pending', 'accepted', 'declined', 'expired', 'cancelled']).optional(),
  direction: z.enum(['incoming', 'outgoing']).optional(),
});

const peerUnavailable = () => new ApiError(404, 'peer_unavailable', "This person isn't available to connect right now.");
const requestExpired = () => new ApiError(409, 'request_expired', 'This request is no longer pending.');
const requestNotFound = () => ApiError.notFound('Connect request not found.');

/** A profile someone can connect with: live and not paused ("Pause All Links"). */
const reachable = (p: Profile | null | undefined): p is Profile => !!p && !p.deletedAt && !p.linksPaused;
const showsInNearby = (p: Profile) => (p.privacySettings as Partial<PrivacySettings> | null)?.showInNearby !== false;

/** A strictly newer edit time than `previous`, so the server write wins LWW on every device. */
const editTime = (previous: Date, now: Date) => (previous >= now ? new Date(previous.getTime() + 1) : now);

interface Target {
  userId: string;
  profile: Profile;
  /** The card the peer advertised (session) or that was scanned (slug); for userId their default card. */
  card: Card | null;
}

export interface AcceptResult {
  request: ConnectRequest;
  fromConnection: Connection;
  toConnection: Connection;
  settled: ConnectRequest[];
}

/** Connect sessions, Nearby peers and connect requests (docs/api/README.md § Connect requests). */
@Injectable()
export class ConnectService {
  private readonly logger = new Logger(ConnectService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly view: ConnectRequestView,
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  // ───────────────────────────── Sessions & peers ─────────────────────────────

  /**
   * The token is what the phone advertises — never the user id. Hidden users (showInNearby = false)
   * still get one; it just never resolves.
   */
  async startSession(userId: string, body: unknown) {
    const input = parse(SessionBody, body);
    await this.ownCard(this.prisma, userId, input.cardId);
    const now = new Date();
    const session = await this.prisma.connectSession.create({
      data: {
        id: randomUUID(),
        userId,
        token: randomToken(24),
        cardId: input.cardId,
        eventId: input.eventId,
        method: input.method,
        expiresAt: new Date(now.getTime() + SESSION_LIFETIME_MS),
      },
    });
    return { sessionId: session.id, discoveryToken: session.token, expiresAt: iso(session.expiresAt) };
  }

  async endSession(userId: string, sessionId: string) {
    let id: string;
    try {
      id = pathUuid(sessionId, 'sessionId');
    } catch {
      return; // never issued by us: nothing to end
    }
    await this.prisma.connectSession.updateMany({ where: { id, userId, endedAt: null }, data: { endedAt: new Date() } });
  }

  async resolvePeers(userId: string, tokensRaw: string | undefined) {
    const tokens = [
      ...new Set(
        (tokensRaw ?? '')
          .split(',')
          .map((t) => t.trim())
          .filter(Boolean),
      ),
    ];
    if (tokens.length > MAX_PEER_TOKENS) throw ApiError.validation({ tokens: `at most ${MAX_PEER_TOKENS} tokens` });
    if (tokens.length === 0) return { items: [], nextCursor: null };
    const now = new Date();
    const sessions = await this.prisma.connectSession.findMany({
      where: { token: { in: tokens }, endedAt: null, expiresAt: { gt: now }, NOT: { userId } },
    });
    const userIds = [...new Set(sessions.map((s) => s.userId))];
    const [profiles, cards, blocked] = await Promise.all([
      this.prisma.profile.findMany({ where: { userId: { in: userIds } } }),
      this.prisma.card.findMany({ where: { id: { in: sessions.map((s) => s.cardId) }, deletedAt: null } }),
      blockedAmong(this.prisma, userId, userIds),
    ]);
    const profileBy = new Map(profiles.map((p) => [p.userId, p]));
    const cardBy = new Map(cards.map((c) => [c.id, c]));
    const sessionBy = new Map(sessions.map((s) => [s.token, s]));

    const items: Record<string, unknown>[] = [];
    for (const token of tokens) {
      const session = sessionBy.get(token);
      if (!session) continue;
      const profile = profileBy.get(session.userId);
      const card = cardBy.get(session.cardId);
      if (!reachable(profile) || !showsInNearby(profile) || blocked.has(session.userId)) continue;
      if (!card || card.userId !== session.userId) continue;
      items.push({
        token,
        userId: session.userId,
        fullName: profile.fullName,
        jobTitle: profile.jobTitle,
        company: profile.company,
        ...(profile.photoUrl ? { avatarUrl: profile.photoUrl } : {}),
        card: cardSnapshot(card, profile, 'public', this.env.WEB_BASE_URL),
      });
    }
    return { items, nextCursor: null };
  }

  // ───────────────────────────── Requests ─────────────────────────────

  async send(userId: string, body: unknown) {
    const input = parse(SendBody, body);
    await this.ownCard(this.prisma, userId, input.cardId);
    const now = new Date();
    const target = await this.resolveTarget(userId, input, now);
    const live = LIVE_METHODS.has(input.method);
    const expiresAt = new Date(now.getTime() + (live ? LIVE_LIFETIME_MS : ASYNC_LIFETIME_MS));
    const effects = new Effects();

    const { request, cancelled, accepted } = await this.prisma.write(async (tx) => {
      // One outstanding live request per requester: a new live one withdraws the previous.
      const previous = live
        ? await tx.connectRequest.findMany({
            where: { fromUserId: userId, status: 'pending', method: { in: [...LIVE_METHODS] }, expiresAt: { gt: now } },
            select: { id: true, toUserId: true },
          })
        : [];
      await this.prisma.lockUsers(tx, [userId, target.userId, ...previous.map((p) => p.toUserId)]);
      const cancelled: ConnectRequest[] = [];
      if (previous.length > 0) {
        const still = await tx.connectRequest.findMany({ where: { id: { in: previous.map((p) => p.id) }, status: 'pending' } });
        for (const r of still) cancelled.push(await this.setCancelled(tx, r, now, effects));
      }

      // Blocked either way: stored so the requester sees it pending → expired, never delivered.
      const suppressed = await blockedBetween(tx, userId, target.userId);
      const fromSeq = await this.bump(tx, effects, userId);
      const toSeq = suppressed ? 0n : await this.bump(tx, effects, target.userId);
      let request = await tx.connectRequest.create({
        data: {
          id: randomUUID(),
          fromUserId: userId,
          toUserId: target.userId,
          fromCardId: input.cardId,
          method: input.method,
          status: 'pending',
          isSuppressed: suppressed,
          eventId: input.eventId,
          eventName: present(input.eventName) ? input.eventName!.trim() : null,
          place: present(input.place) ? input.place!.trim() : null,
          createdAt: now,
          updatedAt: now,
          expiresAt,
          fromSeq,
          toSeq,
        },
      });
      // DEFERRED_WELCOME: the owner pre-approved by sharing their card.
      let accepted: AcceptResult | null = null;
      if (input.method === 'deferred' && !suppressed) {
        accepted = await this.applyAccept(tx, request, target.card?.id ?? null, now, effects);
        request = accepted.request;
      }
      return { request, cancelled, accepted };
    });
    this.records.publish(effects);

    for (const r of cancelled) if (!r.isSuppressed) void this.notifyRecipientOfUpdate(r);
    const requesterView = await this.view.oneToWire(request, userId);
    if (accepted) {
      this.background(
        this.realtime.publish(userId, 'connect.request.updated', { request: requesterView, connection: connectionToWire(accepted.fromConnection) }),
      );
      const me = await this.prisma.profile.findUnique({ where: { userId } });
      this.background(
        this.push.notify(target.userId, {
          type: 'connect_result',
          text: { id: 'connectViaLink', params: { name: this.first(me) } },
          data: { requestId: request.id, connectionId: accepted.toConnection.id },
        }),
      );
    } else if (!request.isSuppressed) {
      const recipientView = await this.view.oneToWire(request, target.userId);
      this.background(this.realtime.publish(target.userId, 'connect.request.received', recipientView));
      const me = await this.prisma.profile.findUnique({ where: { userId } });
      this.background(
        this.push.notify(target.userId, {
          type: 'connect_request',
          text: { id: 'connectRequest', params: { name: this.first(me), eventName: request.eventName || null } },
          // The app's Accept / Decline notification actions.
          category: 'CONNECT_REQUEST',
          data: { requestId: request.id },
        }),
      );
    }
    return requesterView;
  }

  async list(userId: string, query: unknown, cursor?: string, limitRaw?: string) {
    const { status, direction } = parse(ListQuery, query);
    const offset = decodeOffset(cursor);
    const n = Number.parseInt(limitRaw ?? '', 10);
    const limit = Number.isFinite(n) ? Math.min(500, Math.max(1, n)) : 100;
    const now = new Date();
    const outgoing: Prisma.ConnectRequestWhereInput = { fromUserId: userId, ...statusWhere(status, 'outgoing', now) };
    const incoming: Prisma.ConnectRequestWhereInput = { toUserId: userId, isSuppressed: false, ...statusWhere(status, 'incoming', now) };
    const where = direction === 'outgoing' ? outgoing : direction === 'incoming' ? incoming : { OR: [outgoing, incoming] };
    const rows = await this.prisma.connectRequest.findMany({
      where,
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      skip: offset,
      take: limit + 1,
    });
    const page = rows.slice(0, limit);
    return { items: await this.view.toWire(page, userId, this.prisma, now), nextCursor: rows.length > limit ? encodeOffset(offset + limit) : null };
  }

  async get(userId: string, requestId: string) {
    const request = await this.prisma.connectRequest.findUnique({ where: { id: pathUuid(requestId, 'requestId') } });
    if (!request || !this.isVisibleParty(request, userId)) throw requestNotFound();
    return this.view.oneToWire(request, userId);
  }

  async accept(userId: string, requestId: string, body: unknown) {
    const id = pathUuid(requestId, 'requestId');
    const input = parse(AcceptBody, body);
    const now = new Date();
    const effects = new Effects();
    const result = await this.prisma.write(async (tx) => {
      const peek = await tx.connectRequest.findUnique({ where: { id } });
      if (!peek || peek.toUserId !== userId || peek.isSuppressed) throw requestNotFound();
      await this.prisma.lockUsers(tx, [peek.fromUserId, peek.toUserId]);
      const request = await tx.connectRequest.findUniqueOrThrow({ where: { id } });
      if (visibleStatus(request, userId, now) !== 'pending') throw requestExpired();
      await this.ownCard(tx, userId, input.cardId);
      // Blocked after the request was delivered: it can no longer connect.
      if (await blockedBetween(tx, request.fromUserId, request.toUserId)) throw requestExpired();
      return this.applyAccept(tx, request, input.cardId, now, effects);
    });
    this.records.publish(effects);

    const requesterId = result.request.fromUserId;
    const requesterView = await this.view.oneToWire(result.request, requesterId);
    this.background(
      this.realtime.publish(requesterId, 'connect.request.updated', { request: requesterView, connection: connectionToWire(result.fromConnection) }),
    );
    const me = await this.prisma.profile.findUnique({ where: { userId } });
    this.background(
      this.push.notify(requesterId, {
        type: 'connect_result',
        text: { id: 'connectAccepted', params: { name: this.first(me) } },
        data: { requestId: result.request.id, connectionId: result.fromConnection.id },
      }),
    );
    return { request: await this.view.oneToWire(result.request, userId), connection: connectionToWire(result.toConnection) };
  }

  /** Quiet: only the recipient's side changes; the requester keeps seeing pending until expiresAt. */
  async decline(userId: string, requestId: string) {
    const id = pathUuid(requestId, 'requestId');
    const now = new Date();
    const effects = new Effects();
    const request = await this.prisma.write(async (tx) => {
      const peek = await tx.connectRequest.findUnique({ where: { id } });
      if (!peek || peek.toUserId !== userId || peek.isSuppressed) throw requestNotFound();
      await this.prisma.lockUsers(tx, [userId]);
      const current = await tx.connectRequest.findUniqueOrThrow({ where: { id } });
      if (visibleStatus(current, userId, now) !== 'pending') throw requestExpired();
      return tx.connectRequest.update({
        where: { id },
        data: { status: 'declined', respondedAt: now, updatedAt: now, toSeq: await this.bump(tx, effects, userId) },
      });
    });
    this.records.publish(effects);
    return this.view.oneToWire(request, userId);
  }

  /** The requester withdraws; the recipient's overlay disappears (realtime) and its list drops it. */
  async cancel(userId: string, requestId: string) {
    const id = pathUuid(requestId, 'requestId');
    const now = new Date();
    const effects = new Effects();
    const request = await this.prisma.write(async (tx) => {
      const peek = await tx.connectRequest.findUnique({ where: { id } });
      if (!peek || peek.fromUserId !== userId) throw requestNotFound();
      await this.prisma.lockUsers(tx, [peek.fromUserId, peek.toUserId]);
      const current = await tx.connectRequest.findUniqueOrThrow({ where: { id } });
      if (visibleStatus(current, userId, now) !== 'pending') throw requestExpired();
      return this.setCancelled(tx, current, now, effects);
    });
    this.records.publish(effects);
    if (!request.isSuppressed) void this.notifyRecipientOfUpdate(request);
    return this.view.oneToWire(request, userId);
  }

  // ───────────────────────────── Accept (both sides) ─────────────────────────────

  /**
   * Accepts `request` inside the caller's transaction (both users already locked): a mutual
   * connection on each side (reused when one exists for the same Tanishly user), the request settled,
   * and every other pending request between the two settled as accepted too (README rule).
   */
  async applyAccept(tx: Tx, request: ConnectRequest, toCardId: string | null, now: Date, effects: Effects): Promise<AcceptResult> {
    const { fromUserId, toUserId } = request;
    const [profiles, cards] = await Promise.all([
      tx.profile.findMany({ where: { userId: { in: [fromUserId, toUserId] }, deletedAt: null } }),
      tx.card.findMany({ where: { id: { in: [request.fromCardId, ...(toCardId ? [toCardId] : [])] }, deletedAt: null } }),
    ]);
    const profileOf = (id: string) => profiles.find((p) => p.userId === id) ?? null;
    const cardOf = (id: string | null, owner: string) => cards.find((c) => c.id === id && c.userId === owner) ?? null;

    const fromConnection = await this.upsertMutualConnection(tx, effects, request, now, {
      ownerId: fromUserId,
      remoteId: toUserId,
      remoteProfile: profileOf(toUserId),
      remoteCard: cardOf(toCardId, toUserId),
      mySharedCardId: request.fromCardId,
      isRequester: true,
    });
    const toConnection = await this.upsertMutualConnection(tx, effects, request, now, {
      ownerId: toUserId,
      remoteId: fromUserId,
      remoteProfile: profileOf(fromUserId),
      remoteCard: cardOf(request.fromCardId, fromUserId),
      mySharedCardId: toCardId,
      isRequester: false,
    });
    const updated = await tx.connectRequest.update({
      where: { id: request.id },
      data: {
        status: 'accepted',
        respondedAt: now,
        updatedAt: now,
        toCardId,
        fromConnectionId: fromConnection.id,
        toConnectionId: toConnection.id,
        fromSeq: await this.bump(tx, effects, fromUserId),
        toSeq: await this.bump(tx, effects, toUserId),
      },
    });

    const others = await tx.connectRequest.findMany({
      where: {
        id: { not: request.id },
        isSuppressed: false,
        status: { in: ['pending', 'declined'] },
        expiresAt: { gt: now },
        OR: [
          { fromUserId, toUserId },
          { fromUserId: toUserId, toUserId: fromUserId },
        ],
      },
    });
    const connectionOf = (owner: string) => (owner === fromUserId ? fromConnection.id : toConnection.id);
    const settled: ConnectRequest[] = [];
    for (const other of others) {
      settled.push(
        await tx.connectRequest.update({
          where: { id: other.id },
          data: {
            status: 'accepted',
            respondedAt: now,
            updatedAt: now,
            // The card its recipient shared in this connect.
            toCardId: other.toUserId === toUserId ? toCardId : request.fromCardId,
            fromConnectionId: connectionOf(other.fromUserId),
            toConnectionId: connectionOf(other.toUserId),
            fromSeq: await this.bump(tx, effects, other.fromUserId),
            toSeq: await this.bump(tx, effects, other.toUserId),
          },
        }),
      );
    }
    return { request: updated, fromConnection, toConnection, settled };
  }

  private async upsertMutualConnection(
    tx: Tx,
    effects: Effects,
    request: ConnectRequest,
    now: Date,
    side: {
      ownerId: string;
      remoteId: string;
      remoteProfile: Profile | null;
      remoteCard: Card | null;
      mySharedCardId: string | null;
      isRequester: boolean;
    },
  ): Promise<Connection> {
    const { ownerId, remoteId, remoteProfile, remoteCard } = side;
    // Accepted and mutual: the other side's Connections-level fields.
    const snapshot = remoteCard && remoteProfile ? cardSnapshot(remoteCard, remoteProfile, 'connections', this.env.WEB_BASE_URL) : null;
    // Every entry their card shows at Connections level (the snapshot carries the legacy fields only),
    // merged into the connection's list without duplicates; a number already there takes their label.
    const theirContacts = remoteCard && remoteProfile ? cardContactsView(remoteProfile, remoteCard.design as CardDesign, 'connections').contacts : [];
    const context = await this.meetingContext(tx, ownerId, request, now, side.isRequester);
    const seq = await this.bump(tx, effects, ownerId);

    // One live connection per (owner, remoteUserId): connecting again updates it.
    const existing = await tx.connection.findFirst({
      where: { userId: ownerId, remoteUserId: remoteId, deletedAt: null },
      orderBy: { createdAt: 'asc' },
    });
    if (existing) {
      const previousContext = (existing.context ?? {}) as { eventName?: string | null };
      const previousMeetings = (existing.previousMeetings as unknown[] | null) ?? [];
      const moved = (previousContext.eventName ?? null) !== context.eventName ? [existing.context, ...previousMeetings] : previousMeetings;
      const contacts = mergeContacts(connectionContacts(existing), theirContacts, { adoptLabel: true });
      return tx.connection.update({
        where: { id: existing.id },
        data: {
          ...(remoteProfile ? { fullName: remoteProfile.fullName, jobTitle: remoteProfile.jobTitle, company: remoteProfile.company } : {}),
          ...connectionContactData(contacts.contacts),
          ...(remoteProfile?.photoUrl ? { avatarUrl: remoteProfile.photoUrl } : {}),
          ...(snapshot ? { theirCard: snapshot as unknown as Prisma.InputJsonValue } : {}),
          mySharedCardId: side.mySharedCardId,
          context: context as unknown as Prisma.InputJsonValue,
          previousMeetings: moved as Prisma.InputJsonValue,
          eventId: context.eventId,
          isMutual: true,
          updatedAt: editTime(existing.updatedAt, now),
          seq,
        },
      });
    }
    const contacts = mergeContacts([], theirContacts).contacts;
    return tx.connection.create({
      data: {
        id: randomUUID(),
        userId: ownerId,
        remoteUserId: remoteId,
        fullName: remoteProfile?.fullName ?? 'Tanishly user',
        jobTitle: remoteProfile?.jobTitle ?? '',
        company: remoteProfile?.company ?? '',
        ...connectionContactData(contacts),
        avatarUrl: remoteProfile?.photoUrl ?? null,
        ...(snapshot ? { theirCard: snapshot as unknown as Prisma.InputJsonValue } : {}),
        mySharedCardId: side.mySharedCardId,
        source: SOURCE_BY_METHOD[request.method as ConnectMethod] ?? 'connectRequest',
        context: context as unknown as Prisma.InputJsonValue,
        previousMeetings: [],
        eventId: context.eventId,
        note: '',
        tags: [],
        isMerged: false,
        isPendingMerge: false,
        isBlocked: false,
        isMutual: true,
        createdAt: now,
        updatedAt: now,
        seq,
      },
    });
  }

  /**
   * Each owner's side of the meeting: their own active event as a whole (name, venue, city) — never
   * the other person's venue. Without one: what the request carried.
   */
  private async meetingContext(tx: Tx, ownerId: string, request: ConnectRequest, now: Date, isRequester: boolean) {
    const event = await tx.event.findFirst({
      where: { userId: ownerId, status: 'active', deletedAt: null },
      orderBy: [{ startDate: 'desc' }, { id: 'asc' }],
    });
    if (event) {
      return { eventId: event.id, eventName: event.name, place: event.place || null, city: event.city || null, metAt: iso(now) };
    }
    // The request's eventId is the requester's own event; never a foreign id on the recipient's side.
    const ownEvent =
      isRequester && request.eventId
        ? await tx.event.findFirst({ where: { id: request.eventId, userId: ownerId, deletedAt: null }, select: { id: true } })
        : null;
    return { eventId: ownEvent?.id ?? null, eventName: request.eventName, place: request.place, city: null, metAt: iso(now) };
  }

  // ───────────────────────────── Helpers ─────────────────────────────

  private async resolveTarget(userId: string, input: SendBody, now: Date): Promise<Target> {
    let targetId: string;
    let card: Card | null = null;
    if (present(input.toToken)) {
      const session = await this.prisma.connectSession.findUnique({ where: { token: input.toToken!.trim() } });
      if (!session || session.endedAt || session.expiresAt <= now) throw peerUnavailable();
      targetId = session.userId;
      card = await this.prisma.card.findFirst({ where: { id: session.cardId, userId: targetId, deletedAt: null } });
      if (!card) throw peerUnavailable();
    } else if (present(input.toSlug)) {
      card = await this.prisma.card.findUnique({ where: { slug: input.toSlug!.trim().toLowerCase() } });
      if (!card || card.deletedAt) throw peerUnavailable();
      targetId = card.userId;
    } else {
      targetId = input.toUserId!;
    }
    if (targetId === userId) throw ApiError.validation({ toUserId: 'cannot connect with yourself' });

    const [user, profile] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: targetId }, select: { deletedAt: true } }),
      this.prisma.profile.findUnique({ where: { userId: targetId } }),
    ]);
    if (!user || user.deletedAt || !reachable(profile)) throw peerUnavailable();
    // A hidden user's discovery token resolves to nobody — for requests too.
    if (present(input.toToken) && !showsInNearby(profile)) throw peerUnavailable();
    if (!card) {
      const cards = await this.prisma.card.findMany({ where: { userId: targetId, deletedAt: null }, orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }] });
      card = cards.find((c) => c.id === profile.defaultCardId) ?? cards[0] ?? null;
    }
    return { userId: targetId, profile, card };
  }

  private async setCancelled(tx: Tx, request: ConnectRequest, now: Date, effects: Effects) {
    return tx.connectRequest.update({
      where: { id: request.id },
      data: {
        status: 'cancelled',
        respondedAt: now,
        updatedAt: now,
        fromSeq: await this.bump(tx, effects, request.fromUserId),
        ...(request.isSuppressed ? {} : { toSeq: await this.bump(tx, effects, request.toUserId) }),
      },
    });
  }

  private async notifyRecipientOfUpdate(request: ConnectRequest) {
    try {
      const recipientView = await this.view.oneToWire(request, request.toUserId);
      await this.realtime.publish(request.toUserId, 'connect.request.updated', { request: recipientView });
    } catch (error) {
      this.logger.warn({ err: error }, 'connect realtime notification failed');
    }
  }

  private async ownCard(tx: Tx, userId: string, cardId: string): Promise<Card> {
    const card = await tx.card.findFirst({ where: { id: cardId, userId, deletedAt: null } });
    if (!card) throw ApiError.validation({ cardId: 'must be one of your cards' });
    return card;
  }

  private async bump(tx: Tx, effects: Effects, userId: string): Promise<bigint> {
    effects.usersChanged.add(userId);
    return this.prisma.nextSeq(tx, userId);
  }

  private isVisibleParty(r: ConnectRequest, userId: string) {
    return r.fromUserId === userId || (r.toUserId === userId && !r.isSuppressed);
  }

  /** The first name for a push; null when unknown (the catalog says "Someone" in each language). */
  private first(profile: Profile | null): string | null {
    return profile && !profile.deletedAt ? firstName(profile.fullName) || null : null;
  }

  /** Realtime and push are best-effort; they never fail the request. */
  private background(promise: Promise<unknown>) {
    promise.catch((error: unknown) => this.logger.warn({ err: error }, 'connect notification failed'));
  }
}

/** Database filter equal to `visibleStatus(r, viewer) === status` for one direction. */
function statusWhere(status: VisibleStatus | undefined, direction: 'incoming' | 'outgoing', now: Date): Prisma.ConnectRequestWhereInput {
  // The requester never sees "declined": a decline stays pending, then expires.
  const open = direction === 'outgoing' ? { in: ['pending', 'declined'] } : 'pending';
  switch (status) {
    case undefined:
      return {};
    case 'accepted':
    case 'cancelled':
      return { status };
    case 'declined':
      return direction === 'incoming' ? { status: 'declined' } : { id: { in: [] } };
    case 'pending':
      return { status: open, expiresAt: { gt: now } };
    case 'expired':
      return { status: open, expiresAt: { lte: now } };
  }
}
