import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import type { Event } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { PushService } from '../../push/push.service';
import { RecordsService } from '../../records/records.service';
import { JobRunner } from './job-lock';
import { JOBS_DISABLED } from './jobs-config';
import { DEFAULT_TIME_ZONE, endOfLocalDay, isValidTimeZone } from './time-zone';

const BATCH = 200;

export function eventSummaryBody(people: number): string {
  if (people === 0) return 'See how it went and plan your follow-ups.';
  return `You met ${people} ${people === 1 ? 'person' : 'people'}. Add notes and follow-ups while they’re fresh.`;
}

/**
 * Auto-end events (every minute): an `active` event ends at the end of its endDate's calendar day in
 * the owner's time zone (their most recently registered device; Asia/Tashkent without one). The
 * change is a normal synced write (seq bump, `sync.available`), followed once by PUSH_EVENT_SUMMARY.
 */
@Injectable()
export class EventsJob {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly push: PushService,
    private readonly jobs: JobRunner,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE, { name: 'auto-end-events', disabled: JOBS_DISABLED, waitForCompletion: true })
  async tick() {
    await this.jobs.tick('auto-end-events', () => this.process(new Date()));
  }

  runOnce(now = new Date()) {
    return this.jobs.run('auto-end-events', () => this.process(now));
  }

  private async process(now: Date) {
    const zones = new Map<string, string>();
    let ended = 0;
    let summaries = 0;
    // Keyset pages: events whose local day is not over yet stay in the range without blocking others.
    let after: { endDate: Date; id: string } | undefined;
    for (;;) {
      const page = await this.prisma.event.findMany({
        where: {
          status: 'active',
          deletedAt: null,
          endDate: { lte: now },
          ...(after ? { OR: [{ endDate: { gt: after.endDate } }, { endDate: after.endDate, id: { gt: after.id } }] } : {}),
        },
        orderBy: [{ endDate: 'asc' }, { id: 'asc' }],
        take: BATCH,
      });
      for (const event of page) {
        const zone = await this.timeZone(event.userId, zones);
        const endsAt = endOfLocalDay(event.endDate, zone);
        if (endsAt > now) continue;
        const row = await this.end(event, endsAt, now);
        if (!row) continue;
        ended++;
        if (await this.sendSummary(row, now)) summaries++;
      }
      if (page.length < BATCH) break;
      const last = page[page.length - 1]!;
      after = { endDate: last.endDate, id: last.id };
    }
    return { ended, summaries };
  }

  private async timeZone(userId: string, cache: Map<string, string>): Promise<string> {
    let zone = cache.get(userId);
    if (!zone) {
      const device = await this.prisma.device.findFirst({ where: { userId }, orderBy: { updatedAt: 'desc' }, select: { timeZone: true } });
      zone = device && isValidTimeZone(device.timeZone) ? device.timeZone : DEFAULT_TIME_ZONE;
      cache.set(userId, zone);
    }
    return zone;
  }

  private async end(event: Event, endedAt: Date, now: Date): Promise<Event | null> {
    const { result } = await this.records.write(event.userId, async (ctx) => {
      const current = await ctx.tx.event.findUnique({ where: { id: event.id } });
      // Edited meanwhile (resumed with a later end date, ended or deleted on a device): leave it.
      if (!current || current.deletedAt || current.status !== 'active' || current.endDate.getTime() !== event.endDate.getTime()) {
        return null;
      }
      ctx.effects.usersChanged.add(event.userId);
      const row = await ctx.tx.event.update({
        where: { id: event.id },
        data: {
          status: 'ended',
          endedAt,
          // Never older than the stored edit, so devices (which apply updatedAt >= local) take it.
          updatedAt: current.updatedAt > now ? current.updatedAt : now,
          seq: await this.prisma.nextSeq(ctx.tx, event.userId),
        },
      });
      this.records.emitEvent(ctx, row);
      return row;
    });
    return result;
  }

  /** PUSH_EVENT_SUMMARY once per event (summarySentAt is server-internal: no seq bump). */
  private async sendSummary(event: Event, now: Date): Promise<boolean> {
    if (event.summarySentAt) return false;
    const claimed = await this.prisma.event.updateMany({ where: { id: event.id, summarySentAt: null }, data: { summarySentAt: now } });
    if (claimed.count !== 1) return false;
    const prefs = await this.push.prefs(event.userId);
    if (!prefs.eventSummary) return false;
    const people = await this.prisma.connection.count({ where: { userId: event.userId, eventId: event.id, deletedAt: null } });
    await this.push.notify(event.userId, {
      type: 'event_summary',
      title: `${event.name.trim() || 'Your event'} wrapped up`,
      body: eventSummaryBody(people),
      data: { eventId: event.id },
      collapseId: `event-summary.${event.id}`,
    });
    return true;
  }
}
