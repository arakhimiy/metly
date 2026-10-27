import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { hours } from '../../common/time';
import { PrismaService } from '../../prisma/prisma.service';
import { PushService } from '../../push/push.service';
import { TelegramService } from '../telegram/telegram.service';
import { JOBS_DISABLED } from './jobs-config';
import { JobRunner } from './job-lock';

const BATCH = 500;
/** A reminder that could not go out for a day (outage, long downtime) is dropped, not sent late. */
const MAX_LATENESS_MS = hours(24);

interface DueRow {
  id: string;
  user_id: string;
  connection_id: string | null;
  title: string;
  channel: string;
  due_at: Date;
}

/** App categories (FollowUpNotificationCategory.swift): "Open {channel}" needs a value to open. */
export function followUpCategory(channel: string, person: { telegram: string; email: string; phone: string } | null): string {
  const value = !person ? '' : channel === 'telegram' ? person.telegram : channel === 'email' ? person.email : channel === 'call' ? person.phone : '';
  return value.trim() ? `FOLLOW_UP_${channel.toUpperCase()}` : 'FOLLOW_UP';
}

/**
 * Follow-up reminders (every minute): every open follow-up whose dueAt has passed (within the last
 * 24 h) and was not reminded for this dueAt gets one reminder — APNs (PUSH_FOLLOWUP) or the Telegram
 * bot when `notificationPrefs.delivery == telegramBot` and a chat is linked. `remindedForDueAt` is
 * claimed before sending (at most once per dueAt; moving the due date re-arms it). It is
 * server-internal and not part of the wire record, so it does not bump the owner's seq.
 */
@Injectable()
export class RemindersJob {
  constructor(
    private readonly prisma: PrismaService,
    private readonly push: PushService,
    private readonly telegram: TelegramService,
    private readonly jobs: JobRunner,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE, { name: 'followup-reminders', disabled: JOBS_DISABLED, waitForCompletion: true })
  async tick() {
    await this.jobs.tick('followup-reminders', () => this.process(new Date()));
  }

  /** One pass (tests call it directly). Undefined when another instance holds the lock. */
  runOnce(now = new Date()) {
    return this.jobs.run('followup-reminders', () => this.process(now));
  }

  private async process(now: Date) {
    const since = new Date(now.getTime() - MAX_LATENESS_MS);
    let pushed = 0;
    let telegram = 0;
    let skipped = 0;
    // Bounded so a pathological batch can never spin forever; the next tick continues.
    for (let page = 0; page < 100; page++) {
      const due = await this.prisma.$queryRaw<DueRow[]>`
        SELECT id, user_id, connection_id, title, channel, due_at
        FROM follow_ups
        WHERE deleted_at IS NULL AND NOT is_done
          AND due_at <= ${now} AND due_at > ${since}
          AND reminded_for_due_at IS DISTINCT FROM due_at
        ORDER BY due_at, id
        LIMIT ${BATCH}`;
      for (const row of due) {
        const outcome = await this.remind(row);
        if (outcome === 'push') pushed++;
        else if (outcome === 'telegram') telegram++;
        else skipped++;
      }
      if (due.length < BATCH) break;
    }
    return { pushed, telegram, skipped };
  }

  private async remind(row: DueRow): Promise<'push' | 'telegram' | 'skipped'> {
    // Claim first: a concurrent edit that moved dueAt or closed the follow-up wins.
    const claimed = await this.prisma.$executeRaw`
      UPDATE follow_ups SET reminded_for_due_at = due_at
      WHERE id = ${row.id}::uuid AND due_at = ${row.due_at} AND deleted_at IS NULL AND NOT is_done
        AND reminded_for_due_at IS DISTINCT FROM due_at`;
    if (claimed !== 1) return 'skipped';

    const prefs = await this.push.prefs(row.user_id);
    if (!prefs.followUpReminders) return 'skipped';

    const person = row.connection_id
      ? await this.prisma.connection.findFirst({
          where: { id: row.connection_id, userId: row.user_id, deletedAt: null },
          select: { fullName: true, telegram: true, email: true, phone: true },
        })
      : null;
    const personName = person?.fullName.trim() || null;

    if (prefs.delivery === 'telegramBot') {
      const user = await this.prisma.user.findUnique({ where: { id: row.user_id }, select: { telegramChatId: true } });
      if (user?.telegramChatId) {
        const sent = await this.telegram.sendReminder(user.telegramChatId, {
          personName,
          title: row.title,
          channel: row.channel,
          telegramHandle: person?.telegram,
        });
        if (sent) return 'telegram';
        // A dead chat was just unlinked (delivery is back to push), so the push below goes out. A
        // transient bot failure is not retried: the app's local notification covers that case.
      }
    }

    await this.push.notify(row.user_id, {
      type: 'followup_due',
      text: { id: 'followUpDue', params: { personName, title: row.title } },
      data: { followUpId: row.id, ...(row.connection_id ? { connectionId: row.connection_id } : {}) },
      // The app's local fallback uses this request identifier; the push replaces it instead of doubling.
      collapseId: `followup.${row.id.toUpperCase()}`,
      category: followUpCategory(row.channel, person),
      threadId: 'follow-ups',
    });
    return 'push';
  }
}
