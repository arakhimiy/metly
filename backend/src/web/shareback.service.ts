import { randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { randomToken, safeEqual, sha256 } from '../common/crypto';
import { RateLimitStore } from '../common/rate-limit';
import { parse } from '../common/validate';
import type { Card, Connection, Prisma, Profile } from '../generated/prisma/client';
import { SHAREBACK_CONNECTION_TEXT } from '../i18n/messages';
import { userLang } from '../i18n/user-lang';
import { PrismaService } from '../prisma/prisma.service';
import { PushService } from '../push/push.service';
import { RealtimeService } from '../realtime/realtime.service';
import { connectionToWire, contextToJson } from '../records/mappers';
import { RecordsService, type WriteContext } from '../records/records.service';
import { firstName } from '../records/snapshot';
import type { ContactField } from '../records/wire';
import { cleanText, defaultRegion, digitsOnly, normalizePhone, normalizeTelegram, telegramKey } from './shareback-input';
import { WebStatsService } from './web-stats.service';

const optionalText = (max: number) =>
  z
    .string()
    .max(max * 4)
    .nullish()
    .transform((v) => (v ? cleanText(v) : ''));

export const ShareBackBody = z.object({
  name: z
    .string()
    .max(400)
    .transform(cleanText)
    .pipe(z.string().min(1, 'Add your name to send.').max(80, 'Use at most 80 characters.')),
  phone: optionalText(40),
  telegram: optionalText(64),
  metAt: optionalText(120).pipe(z.string().max(120, 'Use at most 120 characters.')),
  platform: z.enum(['ios', 'android', 'inapp', 'desktop']),
  website: z.string().max(2000).nullish(),
  captchaToken: z.string().max(4096).nullish(),
});
export type ShareBackBody = z.infer<typeof ShareBackBody>;

/** README § Share-back: 50 share-backs per card per day (the per-IP budget is on the route). */
const PER_CARD_DAILY = { limit: 50, windowSeconds: 86_400, by: 'ip' as const };

export type MergeResult = 'created' | 'dedupedByPhoneOrTelegram';

interface Accepted {
  shareBackId: string;
  removalToken: string;
}

@Injectable()
export class ShareBackService {
  private readonly logger = new Logger(ShareBackService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly realtime: RealtimeService,
    private readonly push: PushService,
    private readonly rateLimits: RateLimitStore,
    private readonly stats: WebStatsService,
  ) {}

  /** A response for a share-back that is silently discarded (honeypot, paused card, blocked sender). */
  private discarded(): Accepted {
    return { shareBackId: randomUUID(), removalToken: randomToken(24) };
  }

  /**
   * Validates and applies a share-back to an available card (`profile` = the owner's), or discards it.
   * `card` is null for a paused card: still validated, then dropped.
   */
  async receive(card: Card, profile: Profile | null, body: unknown): Promise<Accepted> {
    const input = parse(ShareBackBody, body);
    if (input.website && input.website.trim().length > 0) return this.discarded();

    const region = defaultRegion(profile?.contactFields as ContactField[] | null);
    const phone = input.phone ? normalizePhone(input.phone, region) : null;
    const telegram = input.telegram ? normalizeTelegram(input.telegram) : null;
    const details: Record<string, string> = {};
    if (input.phone && !phone) details.phone = 'Enter a valid phone number.';
    if (input.telegram && !telegram) details.telegram = 'Enter a Telegram username (5–32 letters, digits or _).';
    if (!input.phone && !input.telegram) details.phone = 'Add a phone or Telegram to send.';
    if (Object.keys(details).length > 0) throw ApiError.validation(details);
    if (!profile) return this.discarded();

    if (!this.rateLimits.check(`shareBackPerCard:${card.id}`, PER_CARD_DAILY)) {
      throw new ApiError(429, 'rate_limited', 'This card received too many contacts today. Try again tomorrow.', undefined, {
        'Retry-After': '3600',
      });
    }

    const removalToken = randomToken(24);
    const shareBackId = randomUUID();
    const ownerId = card.userId;
    const placeholder = SHAREBACK_CONNECTION_TEXT[await userLang(this.prisma, ownerId)];
    const { result } = await this.records.write(ownerId, (ctx) =>
      this.apply(ctx, { card, shareBackId, removalToken, name: input.name, phone, telegram, metAt: input.metAt || null, placeholder }),
    );
    if (!result) return { shareBackId, removalToken };
    this.stats.noteBumped(card.id);

    const notice = {
      shareBackId,
      cardId: card.id,
      connection: connectionToWire(result.connection),
      mergeResult: result.mergeResult,
      ...(result.mergeCandidateId ? { mergeCandidateId: result.mergeCandidateId } : {}),
      ...(result.eventName ? { eventName: result.eventName } : {}),
    };
    await this.realtime.publish(ownerId, 'shareback.received', notice).catch((error: unknown) => {
      this.logger.warn({ err: error }, 'shareback realtime failed');
    });
    await this.push
      .notify(ownerId, {
        type: 'shareback_received',
        text: { id: 'shareBackReceived', params: { name: firstName(input.name), context: result.eventName ?? null } },
        data: { connectionId: result.connection.id },
      })
      .catch((error: unknown) => this.logger.warn({ err: error }, 'shareback push failed'));
    return { shareBackId, removalToken };
  }

  /** README § Share-back merge rules, inside the owner's write transaction. Null = discarded. */
  private async apply(
    ctx: WriteContext,
    input: {
      card: Card;
      shareBackId: string;
      removalToken: string;
      name: string;
      phone: string | null;
      telegram: string | null;
      metAt: string | null;
      /** Job title and company of a created connection, in the owner's language. */
      placeholder: { jobTitle: string; company: string };
    },
  ) {
    const { tx, userId: ownerId } = ctx;
    const now = new Date();
    const event = await tx.event.findFirst({
      where: { userId: ownerId, status: 'active', deletedAt: null },
      orderBy: [{ startDate: 'desc' }, { createdAt: 'desc' }],
    });
    const digits = input.phone ? digitsOnly(input.phone) : '';
    const handle = input.telegram ? telegramKey(input.telegram) : '';
    const [twin] = await tx.$queryRaw<{ id: string }[]>`
      SELECT id FROM connections
      WHERE user_id = ${ownerId}::uuid AND deleted_at IS NULL AND (
        (${digits} <> '' AND regexp_replace(phone, '[^0-9]', '', 'g') = ${digits})
        OR (${handle} <> '' AND lower(ltrim(btrim(telegram), '@')) = ${handle})
      )
      ORDER BY created_at ASC
      LIMIT 1`;

    let connection: Connection;
    let mergeResult: MergeResult;
    let mergeCandidateId: string | null = null;
    let addedPhone: string | null = null;
    let addedTelegram: string | null = null;
    let created = false;

    if (twin) {
      // 1. Same phone (digits) or Telegram (case-insensitive) → fill gaps silently.
      const existing = await tx.connection.findUniqueOrThrow({ where: { id: twin.id } });
      // The owner blocked this person: discard (README: blocked senders are dropped silently).
      if (existing.isBlocked) return null;
      mergeResult = 'dedupedByPhoneOrTelegram';
      if (input.phone && existing.phone.trim() === '') addedPhone = input.phone;
      if (input.telegram && existing.telegram.trim() === '') addedTelegram = input.telegram;
      if (addedPhone || addedTelegram) {
        connection = await tx.connection.update({
          where: { id: existing.id },
          data: {
            ...(addedPhone ? { phone: addedPhone } : {}),
            ...(addedTelegram ? { telegram: addedTelegram } : {}),
            updatedAt: existing.updatedAt > now ? new Date(existing.updatedAt.getTime() + 1) : now,
            seq: await this.bump(ctx),
          },
        });
        this.records.emitConnection(ctx, connection);
      } else {
        // Nothing new: leave the record (and its LWW clock) untouched.
        connection = existing;
      }
    } else {
      // 2. New connection. A "Who did you just meet?" placeholder with the same first name is only
      //    suggested — the app asks the owner before merging (PLAN Q18).
      mergeResult = 'created';
      created = true;
      addedPhone = input.phone;
      addedTelegram = input.telegram;
      const first = firstName(input.name).toLowerCase();
      const pending = await tx.connection.findMany({
        where: { userId: ownerId, deletedAt: null, isPendingMerge: true },
        orderBy: { createdAt: 'desc' },
        select: { id: true, fullName: true },
      });
      mergeCandidateId = pending.find((p) => firstName(p.fullName).toLowerCase() === first)?.id ?? null;
      const context = contextToJson({
        eventId: event?.id ?? null,
        eventName: event?.name ?? input.metAt ?? null,
        place: event?.place || null,
        city: event?.city || null,
        metAt: now,
      });
      connection = await tx.connection.create({
        data: {
          id: randomUUID(),
          userId: ownerId,
          remoteUserId: null,
          fullName: input.name,
          jobTitle: input.placeholder.jobTitle,
          company: input.placeholder.company,
          phone: input.phone ?? '',
          email: '',
          telegram: input.telegram ?? '',
          website: '',
          linkedin: '',
          mySharedCardId: input.card.id,
          source: 'webShareBack',
          context: context as Prisma.InputJsonValue,
          previousMeetings: [] as Prisma.InputJsonValue,
          eventId: event?.id ?? null,
          note: '',
          tags: [] as Prisma.InputJsonValue,
          isMerged: false,
          isPendingMerge: false,
          isBlocked: false,
          createdAt: now,
          updatedAt: now,
          seq: await this.bump(ctx),
        },
      });
      this.records.emitConnection(ctx, connection);
    }

    const cardRow = await tx.card.update({
      where: { id: input.card.id },
      data: { shareBacks: { increment: 1 }, seq: await this.bump(ctx) },
    });
    await this.records.emitCard(ctx, cardRow);

    await tx.shareBack.create({
      data: {
        id: input.shareBackId,
        cardId: input.card.id,
        ownerId,
        connectionId: connection.id,
        createdConnection: created,
        addedPhone,
        addedTelegram,
        removalTokenHash: sha256(input.removalToken),
        createdAt: now,
      },
    });
    return { connection, mergeResult, mergeCandidateId, eventName: event?.name ?? null };
  }

  private bump(ctx: WriteContext): Promise<bigint> {
    ctx.effects.usersChanged.add(ctx.userId);
    return this.prisma.nextSeq(ctx.tx, ctx.userId);
  }

  /**
   * "Remove my contact": removes exactly what the share-back added. A connection it created is
   * tombstoned (follow-ups cascade); a merged one loses only the phone/Telegram it filled in, if they
   * still hold those values. Unknown or already removed → no-op.
   */
  async remove(shareBackId: string, token: string | undefined): Promise<void> {
    const row = await this.prisma.shareBack.findUnique({ where: { id: shareBackId } });
    if (!row) return;
    if (!token || !safeEqual(sha256(token), row.removalTokenHash)) throw ApiError.forbidden('This removal link is not valid.');
    if (row.removedAt) return;

    await this.records.write(row.ownerId, async (ctx) => {
      // Re-check under the owner's lock so two removals cannot both apply.
      const fresh = await ctx.tx.shareBack.findUniqueOrThrow({ where: { id: row.id } });
      if (fresh.removedAt) return;
      const now = new Date();
      const connection = fresh.connectionId
        ? await ctx.tx.connection.findFirst({ where: { id: fresh.connectionId, userId: row.ownerId, deletedAt: null } })
        : null;
      if (connection && fresh.createdConnection) {
        const deletedAt = connection.updatedAt > now ? connection.updatedAt : now;
        await this.records.applyTombstone(ctx, { type: 'connection', id: connection.id, deletedAt });
      } else if (connection) {
        const data: Prisma.ConnectionUpdateInput = {};
        if (fresh.addedPhone && connection.phone === fresh.addedPhone) data.phone = '';
        if (fresh.addedTelegram && connection.telegram === fresh.addedTelegram) data.telegram = '';
        if (Object.keys(data).length > 0) {
          const updated = await ctx.tx.connection.update({
            where: { id: connection.id },
            data: {
              ...data,
              updatedAt: connection.updatedAt >= now ? new Date(connection.updatedAt.getTime() + 1) : now,
              seq: await this.bump(ctx),
            },
          });
          this.records.emitConnection(ctx, updated);
        }
      }
      await ctx.tx.shareBack.update({ where: { id: row.id }, data: { removedAt: now } });
    });
  }
}
