// Event writes: the LWW upsert with the Free active-event limit, and the rename cascade into the
// `context.eventName` of connections tagged with the event.
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import type { Event } from '../../generated/prisma/client';
import { EntitlementsService } from '../../subscriptions/entitlements.service';
import type { ApplyResult } from '../changes';
import type { EventIn } from '../wire';
import { lww, type WriteContext } from '../write-context';
import { RecordCore } from './record-core';

@Injectable()
export class EventWriter {
  constructor(
    private readonly core: RecordCore,
    private readonly entitlements: EntitlementsService,
  ) {}

  async upsertEvent(ctx: WriteContext, incoming: EventIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.event.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      this.core.emitEvent(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);
    if (incoming.status === 'active' && live?.status !== 'active' && plan.limits.maxActiveEvents !== null) {
      const active = await tx.event.count({ where: { userId, deletedAt: null, status: 'active', NOT: { id: incoming.id } } });
      if (active >= plan.limits.maxActiveEvents) {
        return {
          status: 'rejected',
          error: ApiError.planLimit('activeEvents', `The Free plan includes ${plan.limits.maxActiveEvents} active event.`),
        };
      }
    }
    const seq = await this.core.bump(ctx);
    const data = {
      name: incoming.name,
      place: incoming.place,
      city: incoming.city,
      startDate: incoming.startDate,
      endDate: incoming.endDate,
      cardId: incoming.cardId,
      status: incoming.status,
      calendarEventIdentifier: incoming.calendarEventIdentifier,
      endedAt: incoming.status === 'ended' ? (incoming.endedAt ?? new Date()) : null,
      // Resuming re-arms the end-of-event summary.
      ...(incoming.status === 'active' ? { summarySentAt: null } : {}),
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
    };
    const row = existing
      ? await tx.event.update({ where: { id: existing.id }, data })
      : await tx.event.create({ data: { ...data, id: incoming.id, userId, createdAt: incoming.createdAt } });

    if (live && live.name !== row.name) await this.cascadeEventRename(ctx, row);
    this.core.emitEvent(ctx, row);
    return { status: 'applied' };
  }

  /** Rename → `context.eventName` of tagged connections; their updatedAt = max(own, event's). */
  private async cascadeEventRename(ctx: WriteContext, event: Event) {
    const tagged = await ctx.tx.connection.findMany({ where: { userId: ctx.userId, eventId: event.id, deletedAt: null } });
    for (const connection of tagged) {
      const context = { ...(connection.context as Record<string, unknown>), eventName: event.name };
      const row = await ctx.tx.connection.update({
        where: { id: connection.id },
        data: {
          context,
          updatedAt: connection.updatedAt > event.updatedAt ? connection.updatedAt : event.updatedAt,
          seq: await this.core.bump(ctx),
        },
      });
      this.core.emitConnection(ctx, row);
    }
  }
}
