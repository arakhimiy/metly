// Follow-up writes: the LWW upsert with the Free open follow-up limit, the all-or-nothing bulk
// upsert, and resolving a merged connection's alias to its survivor.
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { EntitlementsService } from '../../subscriptions/entitlements.service';
import type { ApplyResult } from '../changes';
import type { FollowUpIn } from '../wire';
import { lww, type WriteContext } from '../write-context';
import { RecordCore } from './record-core';

@Injectable()
export class FollowUpWriter {
  constructor(
    private readonly core: RecordCore,
    private readonly entitlements: EntitlementsService,
  ) {}

  async upsertFollowUp(ctx: WriteContext, incoming: FollowUpIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.followUp.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.core.emitFollowUp(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);
    const opensNew = !incoming.isDone && (!live || live.isDone);
    if (opensNew && plan.limits.maxOpenFollowUps !== null) {
      const open = await tx.followUp.count({ where: { userId, deletedAt: null, isDone: false, NOT: { id: incoming.id } } });
      if (open >= plan.limits.maxOpenFollowUps) {
        return {
          status: 'rejected',
          error: ApiError.planLimit('openFollowUps', `The Free plan includes ${plan.limits.maxOpenFollowUps} active reminders.`),
        };
      }
    }
    const connectionId = incoming.connectionId ? await this.resolveConnectionAlias(ctx, incoming.connectionId) : null;
    const seq = await this.core.bump(ctx);
    const data = {
      connectionId,
      title: incoming.title,
      channel: incoming.channel,
      dueAt: incoming.dueAt,
      isDone: incoming.isDone,
      completedAt: incoming.isDone ? (incoming.completedAt ?? incoming.updatedAt) : null,
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.followUp.update({ where: { id: existing.id }, data })
      : await tx.followUp.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });
    this.core.emitFollowUp(ctx, row);
    return { status: 'applied' };
  }

  async resolveConnectionAlias(ctx: WriteContext, connectionId: string): Promise<string> {
    const alias = await ctx.tx.connectionAlias.findUnique({ where: { aliasId: connectionId } });
    return alias && alias.userId === ctx.userId ? alias.survivorId : connectionId;
  }

  /** Bulk create-or-update, all-or-nothing against the Free open follow-up limit. */
  async bulkUpsertFollowUps(ctx: WriteContext, items: FollowUpIn[]): Promise<void> {
    const plan = await ctx.planFor(this.entitlements);
    if (plan.limits.maxOpenFollowUps !== null) {
      const ids = items.map((i) => i.id);
      const stored = await ctx.tx.followUp.findMany({ where: { id: { in: ids } } });
      const storedById = new Map(stored.map((s) => [s.id, s]));
      const openOthers = await ctx.tx.followUp.count({
        where: { userId: ctx.userId, deletedAt: null, isDone: false, NOT: { id: { in: ids } } },
      });
      const openAfter = items.filter((i) => {
        const s = storedById.get(i.id);
        if (s && (s.deletedAt ? s.deletedAt >= i.updatedAt : s.updatedAt > i.updatedAt)) return !s.deletedAt && !s.isDone;
        return !i.isDone;
      }).length;
      if (openOthers + openAfter > plan.limits.maxOpenFollowUps) {
        throw ApiError.planLimit('openFollowUps', `The Free plan includes ${plan.limits.maxOpenFollowUps} active reminders.`);
      }
    }
    for (const item of items) {
      const result = await this.upsertFollowUp(ctx, item);
      if (result.status === 'rejected' && result.error) throw result.error;
    }
  }
}
