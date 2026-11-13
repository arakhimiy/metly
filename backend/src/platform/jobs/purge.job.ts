import { Injectable } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { days, hours } from '../../common/time';
import { Prisma, PrismaService } from '../../prisma/prisma.service';
import { JobRunner } from './job-lock';
import { JOBS_DISABLED } from './jobs-config';

const BATCH = 1000;

/** README § Sync protocol: tombstones live ≥ 90 days. */
export const TOMBSTONE_RETENTION_MS = days(90);

/** Synced tables whose tombstones are purged (the `slugs` registry is never touched). */
const SYNCED_TABLES = ['follow_ups', 'connections', 'events', 'cards', 'profiles'] as const;

/**
 * Tombstone and housekeeping purge (daily, 03:30 UTC). Hard-deletes synced rows tombstoned more than
 * 90 days ago and raises each affected user's `tombstone_floor_seq` to the highest purged seq, so a
 * cursor that could have missed one of them gets `410 cursor_expired` and re-snapshots. Then drops
 * expired operational rows (rate-limit windows, idempotency records, visits, deferred clicks, link tokens, sessions,
 * refresh tokens, aliases, settled connect requests, processed App Store notifications).
 */
@Injectable()
export class PurgeJob {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jobs: JobRunner,
  ) {}

  @Cron('30 3 * * *', { name: 'purge', timeZone: 'UTC', disabled: JOBS_DISABLED, waitForCompletion: true })
  async tick() {
    await this.jobs.tick('purge', () => this.process(new Date()), 60 * 60_000);
  }

  runOnce(now = new Date()) {
    return this.jobs.run('purge', () => this.process(now), 60 * 60_000);
  }

  private async process(now: Date) {
    const tombstoneCutoff = new Date(now.getTime() - TOMBSTONE_RETENTION_MS);
    const tombstones: Record<string, number> = {};
    for (const table of SYNCED_TABLES) tombstones[table] = await this.purgeTombstones(table, tombstoneCutoff);

    const before = (ms: number) => new Date(now.getTime() - ms);
    const p = this.prisma;
    const housekeeping = {
      connectRequests: (
        await p.connectRequest.deleteMany({
          where: {
            OR: [
              { status: { in: ['accepted', 'cancelled'] }, updatedAt: { lt: tombstoneCutoff } },
              // Pending and (silently) declined requests end at expiresAt.
              { status: { in: ['pending', 'declined'] }, expiresAt: { lt: tombstoneCutoff } },
            ],
          },
        })
      ).count,
      rateLimitWindows: (await p.rateLimitWindow.deleteMany({ where: { resetAt: { lt: now } } })).count,
      idempotencyRecords: (await p.idempotencyRecord.deleteMany({ where: { createdAt: { lt: before(hours(24)) } } })).count,
      cardVisits: (await p.cardVisit.deleteMany({ where: { createdAt: { lt: before(days(30)) } } })).count,
      deferredClicks: (await p.deferredClick.deleteMany({ where: { createdAt: { lt: before(days(2)) } } })).count,
      connectSessions: (await p.connectSession.deleteMany({ where: { expiresAt: { lt: before(days(1)) } } })).count,
      refreshTokens: (
        await p.refreshToken.deleteMany({
          where: { OR: [{ expiresAt: { lt: before(days(30)) } }, { revokedAt: { lt: before(days(30)) } }] },
        })
      ).count,
      connectionAliases: (await p.connectionAlias.deleteMany({ where: { createdAt: { lt: tombstoneCutoff } } })).count,
      // Apple redelivers for a few days at most; the ids only guard against duplicates.
      appStoreNotifications: (await p.appStoreNotification.deleteMany({ where: { receivedAt: { lt: tombstoneCutoff } } })).count,
    };
    return { tombstones, housekeeping };
  }

  /** Deletes old tombstones of one table in batches; each batch raises the owners' floors atomically. */
  private async purgeTombstones(table: (typeof SYNCED_TABLES)[number], cutoff: Date): Promise<number> {
    const tableSql = Prisma.raw(table);
    let total = 0;
    for (;;) {
      const purged = await this.prisma.write(async (tx) => {
        const rows = await tx.$queryRaw<{ user_id: string; max_seq: bigint; n: bigint }[]>`
          WITH purged AS (
            DELETE FROM ${tableSql}
            WHERE id IN (
              SELECT id FROM ${tableSql}
              WHERE deleted_at IS NOT NULL AND deleted_at < ${cutoff}
              ORDER BY deleted_at
              LIMIT ${BATCH}
              FOR UPDATE SKIP LOCKED
            )
            RETURNING user_id, seq
          )
          SELECT user_id::text AS user_id, max(seq) AS max_seq, count(*) AS n FROM purged GROUP BY user_id`;
        for (const row of rows) {
          await tx.$executeRaw`
            UPDATE users SET tombstone_floor_seq = GREATEST(tombstone_floor_seq, ${row.max_seq})
            WHERE id = ${row.user_id}::uuid`;
        }
        return rows.reduce((sum, r) => sum + Number(r.n), 0);
      });
      total += purged;
      if (purged < BATCH) return total;
    }
  }
}
