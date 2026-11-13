import { Inject, Injectable } from '@nestjs/common';
import { iso } from '../common/time';
import { ENV, type Env } from '../config/env';
import type { Card, ConnectRequest, Profile } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { cardSnapshot } from '../records/snapshot';

export const LIVE_METHODS = new Set(['nearby', 'tapPhones']);
export const LIVE_LIFETIME_MS = 60_000;
export const ASYNC_LIFETIME_MS = 7 * 86_400_000;

export type VisibleStatus = 'pending' | 'accepted' | 'declined' | 'expired' | 'cancelled';

/**
 * A request as one side sees it. The requester never learns about a decline or a silent drop
 * (blocked): it stays `pending` until expiresAt, then `expired` (SPEC §9 Q9).
 */
export function visibleStatus(r: ConnectRequest, viewerId: string, now = new Date()): VisibleStatus {
  const isRequester = r.fromUserId === viewerId;
  const expired = now >= r.expiresAt;
  if (r.status === 'accepted' || r.status === 'cancelled') return r.status;
  if (isRequester && (r.status === 'declined' || r.isSuppressed)) return expired ? 'expired' : 'pending';
  if (r.status === 'declined') return 'declined';
  return expired ? 'expired' : 'pending';
}

interface Loaded {
  profiles: Map<string, Profile>;
  cards: Map<string, Card>;
}

@Injectable()
export class ConnectRequestView {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Wire `ConnectRequest`s relative to the viewer (profiles and cards loaded in one go). */
  async toWire(requests: ConnectRequest[], viewerId: string, tx: Tx = this.prisma, now = new Date()) {
    if (requests.length === 0) return [];
    const userIds = new Set<string>();
    const cardIds = new Set<string>();
    for (const r of requests) {
      userIds.add(r.fromUserId);
      userIds.add(r.toUserId);
      cardIds.add(r.fromCardId);
      if (r.toCardId) cardIds.add(r.toCardId);
    }
    const [profiles, cards] = await Promise.all([
      tx.profile.findMany({ where: { userId: { in: [...userIds] } } }),
      tx.card.findMany({ where: { id: { in: [...cardIds] } } }),
    ]);
    const loaded: Loaded = {
      profiles: new Map(profiles.map((p) => [p.userId, p])),
      cards: new Map(cards.map((c) => [c.id, c])),
    };
    return requests.map((r) => this.one(r, viewerId, loaded, now));
  }

  async oneToWire(request: ConnectRequest, viewerId: string, tx: Tx = this.prisma) {
    const [wire] = await this.toWire([request], viewerId, tx);
    return wire!;
  }

  private one(r: ConnectRequest, viewerId: string, loaded: Loaded, now: Date) {
    const isRequester = r.fromUserId === viewerId;
    const peerId = isRequester ? r.toUserId : r.fromUserId;
    const peerProfile = loaded.profiles.get(peerId);
    const status = visibleStatus(r, viewerId, now);
    const accepted = status === 'accepted';
    // The card the peer offered (incoming) or returned on accept (outgoing). Connections-level
    // fields only once the connect is accepted (mutual).
    const peerCardId = isRequester ? (accepted ? r.toCardId : null) : r.fromCardId;
    const peerCard = peerCardId ? loaded.cards.get(peerCardId) : undefined;
    const snapshot =
      peerCard && peerProfile && !peerCard.deletedAt
        ? cardSnapshot(peerCard, peerProfile, accepted ? 'connections' : 'public', this.env.WEB_BASE_URL)
        : null;
    const hidesResponse = isRequester && (r.status === 'declined' || r.isSuppressed);
    const updatedAt = hidesResponse ? (status === 'expired' ? r.expiresAt : r.createdAt) : r.updatedAt;
    const wire: Record<string, unknown> = {
      id: r.id,
      direction: isRequester ? 'outgoing' : 'incoming',
      peer: {
        userId: peerId,
        fullName: peerProfile?.fullName ?? 'Nameshake user',
        jobTitle: peerProfile?.jobTitle ?? '',
        company: peerProfile?.company ?? '',
        ...(peerProfile?.photoUrl ? { avatarUrl: peerProfile.photoUrl } : {}),
        ...(snapshot ? { card: snapshot } : {}),
      },
      method: r.method,
      status,
      createdAt: iso(r.createdAt),
      expiresAt: iso(r.expiresAt),
      updatedAt: iso(updatedAt),
    };
    const myCardId = isRequester ? r.fromCardId : r.toCardId;
    if (myCardId) wire.myCardId = myCardId;
    if (r.eventName) wire.eventName = r.eventName;
    if (r.place) wire.place = r.place;
    if (r.respondedAt && !hidesResponse) wire.respondedAt = iso(r.respondedAt);
    return wire;
  }
}
