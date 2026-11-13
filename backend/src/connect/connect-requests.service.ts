// The connect request lifecycle: send (resolving the target), list/get, accept, decline and
// cancel, plus the realtime and push notifications each step sends.
import { randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { decodeOffset, encodeOffset } from '../common/cursor';
import { parse } from '../common/validate';
import type { Card, ConnectRequest, Prisma, Profile } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { PushService } from '../push/push.service';
import { RealtimeService } from '../realtime/realtime.service';
import { connectionToWire } from '../records/mappers';
import { RecordsService } from '../records/records.service';
import { pathUuid } from '../records/rest';
import { firstName } from '../records/snapshot';
import { ConnectMethod, nullableUuid, uuid } from '../records/wire';
import { bumpSeq, Effects } from '../records/write-context';
import { blockedBetween } from './blocks';
import { type AcceptResult, ConnectAcceptService } from './connect-accept.service';
import { ASYNC_LIFETIME_MS, ConnectRequestView, LIVE_LIFETIME_MS, LIVE_METHODS, type VisibleStatus, visibleStatus } from './connect-request.view';
import { ownCard, peerUnavailable, present, reachable, requestExpired, requestNotFound, showsInNearby } from './connect-shared';

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

interface Target {
  userId: string;
  profile: Profile;
  /** The card the peer advertised (session) or that was scanned (slug); for userId their default card. */
  card: Card | null;
}

@Injectable()
export class ConnectRequestsService {
  // Logs under the facade's name, as before the split.
  private readonly logger = new Logger('ConnectService');

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly view: ConnectRequestView,
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
    private readonly acceptor: ConnectAcceptService,
  ) {}

  async send(userId: string, body: unknown) {
    const input = parse(SendBody, body);
    await ownCard(this.prisma, userId, input.cardId);
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
        accepted = await this.acceptor.applyAccept(tx, request, target.card?.id ?? null, now, effects);
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
      await ownCard(tx, userId, input.cardId);
      // Blocked after the request was delivered: it can no longer connect.
      if (await blockedBetween(tx, request.fromUserId, request.toUserId)) throw requestExpired();
      return this.acceptor.applyAccept(tx, request, input.cardId, now, effects);
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

  private bump(tx: Tx, effects: Effects, userId: string): Promise<bigint> {
    return bumpSeq(this.prisma, tx, effects, userId);
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
