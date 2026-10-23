import { Inject, Injectable, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { ApiError } from '../common/api-error';
import { ENV, type Env } from '../config/env';
import { Prisma, PrismaClient } from '../generated/prisma/client';

export type Tx = Prisma.TransactionClient;

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor(@Inject(ENV) env: Env) {
    super({ adapter: new PrismaPg({ connectionString: env.DATABASE_URL }) });
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }

  /**
   * Bumps the user's change counter and returns the new value. The row lock it takes serialises
   * concurrent writers of one user until commit, so commit order equals seq order and a pull can
   * never skip a change that commits later with a smaller seq.
   */
  async nextSeq(tx: Tx, userId: string): Promise<bigint> {
    const rows = await tx.$queryRaw<{ seq: bigint }[]>`UPDATE users SET seq = seq + 1 WHERE id = ${userId}::uuid RETURNING seq`;
    const row = rows[0];
    // The account was deleted while this access token was still valid.
    if (!row) throw ApiError.unauthorized('This account no longer exists.');
    return row.seq;
  }

  /**
   * Locks several users' rows in id order. Call it first in a transaction that writes records of more
   * than one user (accepting a connect request), so two such transactions can never deadlock.
   */
  async lockUsers(tx: Tx, userIds: string[]): Promise<void> {
    const ids = [...new Set(userIds)].sort();
    for (const id of ids) {
      await tx.$queryRaw`SELECT 1 FROM users WHERE id = ${id}::uuid FOR UPDATE`;
    }
  }

  /** Serializable-enough transaction for multi-record writes (default isolation + row locks). */
  write<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return this.$transaction(fn, { maxWait: 10_000, timeout: 30_000 });
  }
}

export { Prisma };
