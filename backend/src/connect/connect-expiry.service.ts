import { Inject, Injectable, Logger, type OnApplicationShutdown, type OnModuleInit } from '@nestjs/common';
import { ENV, type Env } from '../config/env';
import type { ConnectRequest } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { Effects, RecordsService } from '../records/records.service';
import { ConnectRequestView } from './connect-request.view';

export const EXPIRY_INTERVAL_MS = 10_000;
const EXPIRY_BATCH = 100;
/** pg advisory lock key: one instance publishes expiries at a time. */
const EXPIRY_LOCK_KEY = 0x6d65_7401;

/**
 * Expiry is derived from expiresAt, but devices only learn about it through a seq bump: this job bumps
 * the requester's seq (and the recipient's when they saw the request pending) once a request expired,
 * and tells the requester over realtime ("didn't respond"). Disabled under NODE_ENV=test — tests call
 * `publishExpired()` directly.
 */
@Injectable()
export class ConnectExpiryService implements OnModuleInit, OnApplicationShutdown {
  private readonly logger = new Logger(ConnectExpiryService.name);
  private timer: NodeJS.Timeout | undefined;
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly view: ConnectRequestView,
    private readonly realtime: RealtimeService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit() {
    if (this.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => void this.tick(), EXPIRY_INTERVAL_MS);
    this.timer.unref();
  }

  onApplicationShutdown() {
    if (this.timer) clearInterval(this.timer);
  }

  private async tick() {
    if (this.running) return;
    this.running = true;
    try {
      while ((await this.publishExpired()) === EXPIRY_BATCH) {
        // a backlog: keep going until a short batch
      }
    } catch (error) {
      this.logger.warn({ err: error }, 'connect expiry run failed');
    } finally {
      this.running = false;
    }
  }

  /** Publishes up to one batch of newly expired requests; returns how many were published. */
  async publishExpired(now = new Date()): Promise<number> {
    const effects = new Effects();
    const published = await this.prisma.write(async (tx) => {
      const lock = await tx.$queryRaw<{ locked: boolean }[]>`SELECT pg_try_advisory_xact_lock(${EXPIRY_LOCK_KEY}::bigint) AS locked`;
      if (!lock[0]?.locked) return [];
      const where = { expiryPublishedAt: null, expiresAt: { lte: now }, status: { in: ['pending', 'declined'] } };
      const due = await tx.connectRequest.findMany({
        where,
        orderBy: { expiresAt: 'asc' },
        take: EXPIRY_BATCH,
        select: { id: true, fromUserId: true, toUserId: true },
      });
      if (due.length === 0) return [];
      await this.prisma.lockUsers(tx, due.flatMap((r) => [r.fromUserId, r.toUserId]));
      // Re-read under the locks: an accept or cancel may have committed in between.
      const fresh = await tx.connectRequest.findMany({ where: { ...where, id: { in: due.map((r) => r.id) } } });
      const out: { request: ConnectRequest; recipientSaw: boolean }[] = [];
      for (const r of fresh) {
        // The recipient's view changes only when they still saw it pending (a decline stays declined).
        const recipientSaw = r.status === 'pending' && !r.isSuppressed;
        effects.usersChanged.add(r.fromUserId);
        const fromSeq = await this.prisma.nextSeq(tx, r.fromUserId);
        let toSeq = r.toSeq;
        if (recipientSaw) {
          effects.usersChanged.add(r.toUserId);
          toSeq = await this.prisma.nextSeq(tx, r.toUserId);
        }
        const request = await tx.connectRequest.update({
          where: { id: r.id },
          data: { fromSeq, toSeq, expiryPublishedAt: now, ...(recipientSaw ? { updatedAt: r.expiresAt } : {}) },
        });
        out.push({ request, recipientSaw });
      }
      return out;
    });
    this.records.publish(effects);

    for (const { request, recipientSaw } of published) {
      try {
        const [requesterView] = await this.view.toWire([request], request.fromUserId);
        await this.realtime.publish(request.fromUserId, 'connect.request.updated', { request: requesterView });
        if (recipientSaw) {
          const [recipientView] = await this.view.toWire([request], request.toUserId);
          await this.realtime.publish(request.toUserId, 'connect.request.updated', { request: recipientView });
        }
      } catch (error) {
        this.logger.warn({ err: error }, 'connect expiry notification failed');
      }
    }
    return published.length;
  }
}
