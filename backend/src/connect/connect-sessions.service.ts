// Connect sessions and Nearby peers: starting/ending the discovery session a phone advertises,
// and resolving advertised tokens to the people behind them.
import { randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { randomToken } from '../common/crypto';
import { iso, minutes } from '../common/time';
import { parse } from '../common/validate';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { pathUuid } from '../records/rest';
import { cardSnapshot } from '../records/snapshot';
import { ConnectMethod, nullableUuid, uuid } from '../records/wire';
import { blockedAmong } from './blocks';
import { ownCard, reachable, showsInNearby } from './connect-shared';

export const SESSION_LIFETIME_MS = minutes(10);
export const MAX_PEER_TOKENS = 50;

const SessionBody = z.object({ cardId: uuid, eventId: nullableUuid, method: ConnectMethod });

@Injectable()
export class ConnectSessionsService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * The token is what the phone advertises — never the user id. Hidden users (showInNearby = false)
   * still get one; it just never resolves.
   */
  async startSession(userId: string, body: unknown) {
    const input = parse(SessionBody, body);
    await ownCard(this.prisma, userId, input.cardId);
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
}
