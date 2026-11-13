// Tombstones pushed through sync for every record type, and the cascades a delete triggers
// (follow-ups of a connection, event tags on connections, a card's public content).
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import type { Tx } from '../../prisma/prisma.service';
import type { ApplyResult } from '../changes';
import type { SyncRecordType, TombstoneIn } from '../wire';
import type { WriteContext } from '../write-context';
import { RecordCore } from './record-core';

@Injectable()
export class TombstoneWriter {
  constructor(private readonly core: RecordCore) {}

  async applyTombstone(ctx: WriteContext, t: TombstoneIn): Promise<ApplyResult> {
    switch (t.type) {
      case 'profile':
        return this.tombstoneRow(ctx, t, 'profile');
      case 'card':
        return this.tombstoneRow(ctx, t, 'card');
      case 'event':
        return this.tombstoneRow(ctx, t, 'event');
      case 'connection':
        return this.tombstoneRow(ctx, t, 'connection');
      case 'followUp':
        return this.tombstoneRow(ctx, t, 'followUp');
      case 'connectRequest':
        // Requests change only through the connect endpoints.
        return { status: 'rejected', error: ApiError.badRequest('Connect requests cannot be deleted through sync.') };
    }
  }

  private async tombstoneRow(ctx: WriteContext, t: TombstoneIn, type: Exclude<SyncRecordType, 'connectRequest'>): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const delegate = this.delegate(tx, type);
    const existing = (await delegate.findUnique({ where: { id: t.id } })) as
      | { id: string; userId: string; updatedAt: Date; deletedAt: Date | null }
      | null;
    if (!existing) {
      // Never reached the server; nothing to delete, but confirm so the device can forget it.
      ctx.out.tombstone(type, t.id, t.deletedAt);
      return { status: 'applied' };
    }
    if (existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    if (existing.deletedAt) {
      ctx.out.tombstone(type, t.id, existing.deletedAt);
      return { status: 'applied' };
    }
    if (existing.updatedAt > t.deletedAt) {
      await this.core.emitAny(ctx, type, existing);
      return { status: 'stale' };
    }
    const seq = await this.core.bump(ctx);
    await delegate.update({ where: { id: t.id }, data: { deletedAt: t.deletedAt, seq } });
    ctx.out.tombstone(type, t.id, t.deletedAt);
    await this.cascadeDelete(ctx, type, t.id, t.deletedAt);
    return { status: 'applied' };
  }

  async cascadeDelete(ctx: WriteContext, type: SyncRecordType, id: string, deletedAt: Date) {
    const { tx, userId } = ctx;
    if (type === 'connection') {
      const children = await tx.followUp.findMany({ where: { userId, connectionId: id, deletedAt: null } });
      for (const child of children) {
        await tx.followUp.update({ where: { id: child.id }, data: { deletedAt, seq: await this.core.bump(ctx) } });
        ctx.out.tombstone('followUp', child.id, deletedAt);
      }
    } else if (type === 'event') {
      const tagged = await tx.connection.findMany({ where: { userId, eventId: id, deletedAt: null } });
      for (const connection of tagged) {
        const row = await tx.connection.update({ where: { id: connection.id }, data: { eventId: null, seq: await this.core.bump(ctx) } });
        this.core.emitConnection(ctx, row);
      }
    } else if (type === 'card') {
      // The page, vCard and Wallet pass now say "deleted": that is a public content change.
      await tx.card.update({ where: { id }, data: { contentUpdatedAt: new Date() } });
      ctx.effects.cardsContentChanged.add(id);
    }
  }

  private delegate(tx: Tx, type: Exclude<SyncRecordType, 'connectRequest'>) {
    const delegates = {
      profile: tx.profile,
      card: tx.card,
      event: tx.event,
      connection: tx.connection,
      followUp: tx.followUp,
    } as const;
    return delegates[type] as unknown as {
      findUnique(args: { where: { id: string } }): Promise<unknown>;
      update(args: { where: { id: string }; data: Record<string, unknown> }): Promise<unknown>;
    };
  }
}
