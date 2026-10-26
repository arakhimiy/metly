import { Injectable } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { iso } from '../common/time';
import { parse } from '../common/validate';
import type { Block, Connection } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';
import { connectionToWire } from '../records/mappers';
import { RecordsService, type WriteContext } from '../records/records.service';
import { pathUuid } from '../records/rest';
import { nullableUuid } from '../records/wire';

const BlockBody = z
  .object({ userId: nullableUuid, connectionId: nullableUuid })
  .refine((b) => b.userId !== null || b.connectionId !== null, { message: 'userId or connectionId is required', path: ['userId'] });

function blockToWire(b: { blockedUserId: string | null; connectionId: string | null; fullName: string; createdAt: Date }) {
  return {
    ...(b.blockedUserId ? { userId: b.blockedUserId } : {}),
    ...(b.connectionId ? { connectionId: b.connectionId } : {}),
    fullName: b.fullName,
    blockedAt: iso(b.createdAt),
  };
}

/**
 * Blocked people. Effects (enforced where they apply): my public profile 404s for them, I vanish from
 * their Nearby results, their connect requests are suppressed and their share-backs discarded.
 */
@Injectable()
export class BlocksService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
  ) {}

  /** Block rows plus connections blocked on a device (synced `isBlocked`) without one. */
  async list(userId: string) {
    const [blocks, connections] = await Promise.all([
      this.prisma.block.findMany({ where: { userId }, orderBy: [{ createdAt: 'desc' }, { id: 'asc' }] }),
      this.prisma.connection.findMany({ where: { userId, isBlocked: true, deletedAt: null } }),
    ]);
    const covered = new Set(blocks.flatMap((b) => [b.blockedUserId, b.connectionId].filter((v): v is string => v !== null)));
    const extra = connections
      .filter((c) => !covered.has(c.id) && !(c.remoteUserId && covered.has(c.remoteUserId)))
      .map((c) => ({ blockedUserId: c.remoteUserId, connectionId: c.id, fullName: c.fullName, createdAt: c.updatedAt }));
    const items = [...blocks, ...extra].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).map(blockToWire);
    return { items, nextCursor: null };
  }

  async block(userId: string, body: unknown) {
    const input = parse(BlockBody, body);
    if (input.connectionId) return blockToWire((await this.blockConnection(userId, input.connectionId)).block);

    const blockedId = input.userId!;
    if (blockedId === userId) throw ApiError.validation({ userId: 'cannot block yourself' });
    const target = await this.prisma.user.findUnique({ where: { id: blockedId }, select: { id: true, profile: { select: { fullName: true } } } });
    if (!target) throw ApiError.notFound('User not found.');
    const { result } = await this.records.write(userId, async (ctx) => {
      // My connections to them are blocked too (unblocking clears them again).
      const connections = await ctx.tx.connection.findMany({
        where: { userId, remoteUserId: blockedId, deletedAt: null },
        orderBy: { createdAt: 'asc' },
      });
      for (const c of connections) if (!c.isBlocked) await this.setBlocked(ctx, c, true);
      const fullName = connections[0]?.fullName || target.profile?.fullName || 'Tanishly user';
      return this.upsertBlock(ctx.tx, userId, blockedId, connections[0]?.id ?? null, fullName);
    });
    return blockToWire(result);
  }

  /** POST /v1/connections/{id}/block and POST /v1/me/blocks {connectionId}. */
  async blockConnection(userId: string, connectionIdRaw: string) {
    const connectionId = pathUuid(connectionIdRaw, 'connectionId');
    const { result } = await this.records.write(userId, async (ctx) => {
      const connection = await ctx.tx.connection.findFirst({ where: { id: connectionId, userId, deletedAt: null } });
      if (!connection) throw ApiError.notFound('Connection not found.');
      const row = connection.isBlocked ? connection : await this.setBlocked(ctx, connection, true);
      const remote = connection.remoteUserId && connection.remoteUserId !== userId ? connection.remoteUserId : null;
      const block = await this.upsertBlock(ctx.tx, userId, remote, connection.id, connection.fullName);
      return { block, connection: row };
    });
    return { block: result.block, connection: connectionToWire(result.connection) };
  }

  /** `id` is the blocked user's id, or — for a block of a non-Tanishly contact — the connection id. */
  async unblock(userId: string, idRaw: string) {
    const id = pathUuid(idRaw, 'userId');
    await this.records.write(userId, async (ctx) => {
      await ctx.tx.block.deleteMany({ where: { userId, OR: [{ blockedUserId: id }, { connectionId: id }] } });
      const connections = await ctx.tx.connection.findMany({
        where: { userId, isBlocked: true, deletedAt: null, OR: [{ remoteUserId: id }, { id }] },
      });
      for (const c of connections) await this.setBlocked(ctx, c, false);
    });
  }

  private async setBlocked(ctx: WriteContext, connection: Connection, isBlocked: boolean) {
    const now = new Date();
    ctx.effects.usersChanged.add(ctx.userId);
    const row = await ctx.tx.connection.update({
      where: { id: connection.id },
      data: {
        isBlocked,
        // Strictly newer than the stored edit, so this server write wins LWW on every device.
        updatedAt: connection.updatedAt >= now ? new Date(connection.updatedAt.getTime() + 1) : now,
        seq: await this.prisma.nextSeq(ctx.tx, ctx.userId),
      },
    });
    this.records.emitConnection(ctx, row);
    return row;
  }

  private async upsertBlock(tx: Tx, userId: string, blockedUserId: string | null, connectionId: string | null, fullName: string): Promise<Block> {
    if (blockedUserId) {
      const block = await tx.block.upsert({
        where: { userId_blockedUserId: { userId, blockedUserId } },
        create: { userId, blockedUserId, connectionId, fullName },
        update: {},
      });
      if (!block.connectionId && connectionId) return tx.block.update({ where: { id: block.id }, data: { connectionId } });
      return block;
    }
    const existing = await tx.block.findFirst({ where: { userId, blockedUserId: null, connectionId } });
    return existing ?? tx.block.create({ data: { userId, blockedUserId: null, connectionId, fullName } });
  }
}
