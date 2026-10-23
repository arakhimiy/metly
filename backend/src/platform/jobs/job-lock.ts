import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

/** First key of the two-int advisory lock: "Metl". */
const LOCK_NAMESPACE = 0x4d65746c;

/**
 * Runs `fn` only if this instance wins the cluster-wide advisory lock for `job`. The lock is a
 * transaction-level lock held by an otherwise idle transaction for as long as `fn` runs, so it is
 * released even if the process dies; `fn` does its own writes on other connections.
 * Returns undefined when another instance (or an earlier tick of this one) is still running it.
 */
@Injectable()
export class JobRunner {
  private readonly running = new Set<string>();
  private readonly logger = new Logger('Jobs');

  constructor(private readonly prisma: PrismaService) {}

  async run<T>(job: string, fn: () => Promise<T>, timeoutMs = 10 * 60_000): Promise<T | undefined> {
    if (this.running.has(job)) return undefined;
    this.running.add(job);
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const rows = await tx.$queryRaw<{ locked: boolean }[]>`
            SELECT pg_try_advisory_xact_lock(${LOCK_NAMESPACE}::int, hashtext(${job})) AS locked`;
          if (!rows[0]?.locked) return undefined;
          return fn();
        },
        { maxWait: 10_000, timeout: timeoutMs },
      );
    } finally {
      this.running.delete(job);
    }
  }

  /** Timer entry point: never lets a failing job crash the scheduler. */
  async tick(job: string, fn: () => Promise<unknown>, timeoutMs?: number): Promise<void> {
    try {
      const result = await this.run(job, fn, timeoutMs);
      if (result !== undefined) this.logger.debug({ job, result }, 'job ran');
    } catch (error) {
      this.logger.error({ err: error, job }, 'job failed');
    }
  }
}
