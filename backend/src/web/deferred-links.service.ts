import { randomUUID } from 'node:crypto';
import { Inject, Injectable } from '@nestjs/common';
import { z } from 'zod';
import { randomToken } from '../common/crypto';
import { hours } from '../common/time';
import { parse } from '../common/validate';
import { ENV, type Env } from '../config/env';
import type { DeferredClick } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { cardSnapshot } from '../records/snapshot';
import { pickClick } from './deferred-match';
import { PublicCardService } from './public-card.service';
import { ipPrefix, isBot } from './visitor';

/** Fingerprint matches only look this far back (openapi: clicks are kept for matching for 2 h). */
const FINGERPRINT_WINDOW_MS = hours(2);
/** An explicit token (App Clip / pasteboard) is unambiguous, so it may be redeemed a little later. */
const TOKEN_WINDOW_MS = hours(24);

const ClaimBody = z.object({
  installId: z.string().trim().min(1).max(200),
  token: z.string().trim().max(200).nullish(),
  fingerprint: z.object({
    model: z.string().max(100),
    osVersion: z.string().max(50),
    locale: z.string().max(50),
    timeZone: z.string().max(100),
    preferredLanguages: z.array(z.string().max(50)).max(20),
  }),
});

const TIME_ZONE = /^[A-Za-z0-9_+\-/]{1,64}$/;
const LOCALE = /^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8}){0,3}$/;

@Injectable()
export class DeferredLinksService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly cards: PublicCardService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** "Get the app" on a card page. Returns null for bots (nothing stored). */
  async recordClick(
    card: { id: string; userId: string },
    visitor: { ip: string; userAgent: string; acceptLanguage?: string; locale?: string; timeZone?: string },
  ): Promise<DeferredClick | null> {
    if (isBot(visitor.userAgent)) return null;
    const event = await this.prisma.event.findFirst({
      where: { userId: card.userId, status: 'active', deletedAt: null },
      orderBy: [{ startDate: 'desc' }, { createdAt: 'desc' }],
      select: { name: true },
    });
    const headerLocale = (visitor.acceptLanguage ?? '').split(',')[0]?.split(';')[0]?.trim();
    const locale = [visitor.locale, headerLocale].find((l) => l && LOCALE.test(l)) ?? null;
    const timeZone = visitor.timeZone && TIME_ZONE.test(visitor.timeZone) ? visitor.timeZone : null;
    return this.prisma.deferredClick.create({
      data: {
        id: randomUUID(),
        token: randomToken(16),
        cardId: card.id,
        ownerId: card.userId,
        eventName: event?.name ?? null,
        ipPrefix: ipPrefix(visitor.ip),
        userAgent: visitor.userAgent.slice(0, 512),
        locale,
        timeZone,
      },
    });
  }

  /**
   * Explicit token first, else a confident fingerprint match (same network prefix within 2 h, then
   * time zone, OS major, device family and locale — see deferred-match.ts). Single use; one successful
   * claim per installId (the same install asking again gets the same invite).
   */
  async claim(body: unknown, ip: string): Promise<{ invite: Record<string, unknown> | null }> {
    const input = parse(ClaimBody, body);
    const now = Date.now();

    const previous = await this.prisma.deferredClick.findUnique({ where: { claimedInstallId: input.installId } });
    if (previous) return { invite: await this.invite(previous) };

    let click: DeferredClick | null = null;
    if (input.token) {
      const byToken = await this.prisma.deferredClick.findUnique({ where: { token: input.token } });
      if (byToken && !byToken.claimedAt && byToken.createdAt.getTime() >= now - TOKEN_WINDOW_MS) click = byToken;
    }
    if (!click) {
      const candidates = await this.prisma.deferredClick.findMany({
        where: { ipPrefix: ipPrefix(ip), claimedAt: null, createdAt: { gte: new Date(now - FINGERPRINT_WINDOW_MS) } },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });
      click = pickClick(candidates, input.fingerprint);
    }
    if (!click) return { invite: null };

    const invite = await this.invite(click);
    if (!invite) return { invite: null };
    try {
      const claimed = await this.prisma.deferredClick.updateMany({
        where: { id: click.id, claimedAt: null },
        data: { claimedAt: new Date(), claimedInstallId: input.installId },
      });
      if (claimed.count === 0) return { invite: null };
    } catch {
      // claimedInstallId is unique: a concurrent claim by the same install won — answer with its invite.
      const winner = await this.prisma.deferredClick.findUnique({ where: { claimedInstallId: input.installId } });
      return { invite: winner ? await this.invite(winner) : null };
    }
    return { invite };
  }

  /** openapi `DeferredInvite`, or null when the card is no longer shared (paused, deleted). */
  private async invite(click: DeferredClick): Promise<Record<string, unknown> | null> {
    const card = await this.prisma.card.findUnique({ where: { id: click.cardId }, select: { slug: true } });
    if (!card?.slug) return null;
    const resolved = await this.cards.resolve(card.slug);
    if (resolved.status !== 'available') return null;
    const view = this.cards.view(resolved);
    const snapshot = cardSnapshot(resolved.card, resolved.profile, 'public', this.env.WEB_BASE_URL);
    return {
      inviteId: click.id,
      owner: {
        userId: resolved.card.userId,
        fullName: view.fullName,
        jobTitle: resolved.profile.jobTitle,
        company: resolved.profile.company,
        ...(view.photoUrl ? { avatarUrl: view.photoUrl } : {}),
        card: snapshot,
      },
      cardSlug: view.slug,
      card: snapshot,
      ...(click.eventName ? { eventName: click.eventName } : {}),
      createdAt: click.createdAt.toISOString(),
    };
  }
}
