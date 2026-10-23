import { Inject, Injectable, Logger, type OnApplicationShutdown } from '@nestjs/common';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { RecordsService } from '../records/records.service';
import { isBot, visitorHash } from './visitor';

export type WebEventType = 'view' | 'save' | 'copy_phone' | 'copy_email' | 'telegram_open' | 'get_app';

/** Visits of one visitor to one card are counted once per window, per event type. */
const DEDUPE_MINUTES = 30;
/** Stats changes reach the owner's devices at most this often per card. */
const SEQ_THROTTLE_MS = 60_000;

/**
 * Web analytics → card stats (`views`, `saves`, `scans`; `shareBacks` is bumped by the share-back
 * transaction itself).
 *
 * Counting: one `card_visits` row per (card, visitor, type) per 30 minutes; the visitor is an HMAC of
 * IP + user agent + card salted with JWT_SECRET, so raw IPs are never stored. Views are counted from
 * the page's beacon only (`POST …/events` type `view`), never on the server render, so link-preview
 * fetchers and no-JS crawlers do not count and nothing is counted twice. `?src=qr` turns the view into
 * a scan as well. "Save to Contacts" is counted by the `.vcf` download (and a `save` event shares the
 * same de-duplication key, so both together still count once).
 *
 * Sync: counters are updated in place without touching the owner's change counter. The card's `seq`
 * is bumped (so `card.stats` syncs) at most once per card per minute: the first change bumps
 * immediately, later ones schedule a single trailing bump at the end of the minute. The throttle is
 * per instance and in memory; a restart drops a pending trailing bump, and the next stat change (or
 * any other card write) publishes the counts — stats may lag a few minutes, as the contract allows.
 */
@Injectable()
export class WebStatsService implements OnApplicationShutdown {
  private readonly logger = new Logger(WebStatsService.name);
  private readonly lastBump = new Map<string, number>();
  private readonly timers = new Map<string, NodeJS.Timeout>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /** Records one web event; bots and repeats inside the window are ignored. */
  async record(
    card: { id: string; userId: string },
    event: { type: WebEventType; source?: 'qr' | 'link' | null },
    visitor: { ip: string; userAgent: string },
  ): Promise<{ counted: boolean }> {
    if (isBot(visitor.userAgent)) return { counted: false };
    const hash = visitorHash(this.env.JWT_SECRET, visitor.ip, visitor.userAgent, card.id);
    const views = event.type === 'view' && (await this.firstInWindow(card.id, hash, 'view')) ? 1 : 0;
    const scans = event.type === 'view' && event.source === 'qr' && (await this.firstInWindow(card.id, hash, 'scan')) ? 1 : 0;
    const saves = event.type === 'save' && (await this.firstInWindow(card.id, hash, 'save')) ? 1 : 0;
    if (event.type !== 'view' && event.type !== 'save') await this.firstInWindow(card.id, hash, event.type);
    if (views + scans + saves === 0) return { counted: false };
    const updated = await this.prisma.card.updateMany({
      where: { id: card.id, deletedAt: null },
      data: { views: { increment: views }, scans: { increment: scans }, saves: { increment: saves } },
    });
    if (updated.count > 0) await this.scheduleSync(card);
    return { counted: updated.count > 0 };
  }

  /** Inserts the visit unless the same visitor did the same thing within the window. */
  private async firstInWindow(cardId: string, hash: string, type: string): Promise<boolean> {
    const inserted = await this.prisma.$executeRaw`
      INSERT INTO card_visits (card_id, visitor_hash, type, created_at)
      SELECT ${cardId}::uuid, ${hash}, ${type}, now()
      WHERE NOT EXISTS (
        SELECT 1 FROM card_visits
        WHERE card_id = ${cardId}::uuid AND visitor_hash = ${hash} AND type = ${type}
          AND created_at > now() - make_interval(mins => ${DEDUPE_MINUTES}::int)
      )`;
    return inserted === 1;
  }

  /** Someone else (the share-back transaction) just bumped this card's seq. */
  noteBumped(cardId: string) {
    this.lastBump.set(cardId, Date.now());
  }

  private async scheduleSync(card: { id: string; userId: string }): Promise<void> {
    const now = Date.now();
    const last = this.lastBump.get(card.id) ?? 0;
    if (now - last >= SEQ_THROTTLE_MS) {
      this.lastBump.set(card.id, now);
      this.sweep(now);
      await this.bumpSeq(card);
      return;
    }
    if (this.timers.has(card.id)) return;
    const timer = setTimeout(() => {
      this.timers.delete(card.id);
      this.lastBump.set(card.id, Date.now());
      void this.bumpSeq(card);
    }, last + SEQ_THROTTLE_MS - now);
    timer.unref();
    this.timers.set(card.id, timer);
  }

  private async bumpSeq(card: { id: string; userId: string }) {
    try {
      await this.records.write(card.userId, async (ctx) => {
        const row = await ctx.tx.card.findUnique({ where: { id: card.id }, select: { deletedAt: true } });
        if (!row || row.deletedAt) return;
        const seq = await this.prisma.nextSeq(ctx.tx, card.userId);
        ctx.effects.usersChanged.add(card.userId);
        await ctx.tx.card.update({ where: { id: card.id }, data: { seq } });
      });
    } catch (error) {
      this.logger.warn({ err: error, cardId: card.id }, 'could not publish card stats');
    }
  }

  private sweep(now: number) {
    if (this.lastBump.size < 10_000) return;
    for (const [id, at] of this.lastBump) if (now - at >= SEQ_THROTTLE_MS) this.lastBump.delete(id);
  }

  onApplicationShutdown() {
    for (const timer of this.timers.values()) clearTimeout(timer);
    this.timers.clear();
  }
}
