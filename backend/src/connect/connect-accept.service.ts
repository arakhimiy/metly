// Accepting a connect request on both sides inside the caller's transaction: the mutual
// connection each owner gets (with its meeting context), and settling the pair's other requests.
import { randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { iso } from '../common/time';
import { ENV, type Env } from '../config/env';
import type { Card, Connection, ConnectRequest, Prisma, Profile } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { cardContactsView, connectionContactData, connectionContacts, mergeContacts } from '../records/contacts';
import { cardSnapshot } from '../records/snapshot';
import type { CardDesign, ConnectMethod, ConnectionSource } from '../records/wire';
import { bumpSeq, type Effects } from '../records/write-context';

const SOURCE_BY_METHOD: Record<ConnectMethod, ConnectionSource> = {
  nearby: 'nearby',
  tapPhones: 'tapPhones',
  scan: 'scanQR',
  deferred: 'deferredLink',
  emailLookup: 'connectRequest',
};

/** A strictly newer edit time than `previous`, so the server write wins LWW on every device. */
const editTime = (previous: Date, now: Date) => (previous >= now ? new Date(previous.getTime() + 1) : now);

export interface AcceptResult {
  request: ConnectRequest;
  fromConnection: Connection;
  toConnection: Connection;
  settled: ConnectRequest[];
}

@Injectable()
export class ConnectAcceptService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * Accepts `request` inside the caller's transaction (both users already locked): a mutual
   * connection on each side (reused when one exists for the same Nameshake user), the request settled,
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
        fullName: remoteProfile?.fullName ?? 'Nameshake user',
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

  private bump(tx: Tx, effects: Effects, userId: string): Promise<bigint> {
    return bumpSeq(this.prisma, tx, effects, userId);
  }
}
