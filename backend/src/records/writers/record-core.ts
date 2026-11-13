// The small core every record writer shares: the per-user seq bump, emitting canonical rows into
// the transaction's change set, and publishing collected side effects once a transaction committed.
import { Inject, Injectable } from '@nestjs/common';
import { DomainEvents } from '../../common/domain-events';
import { ENV, type Env } from '../../config/env';
import type { Card, Connection, Event, FollowUp, Profile } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { cardToWire, connectionToWire, eventToWire, followUpToWire, profileToWire } from '../mappers';
import type { SyncRecordType } from '../wire';
import { bumpSeq, type Effects, type WriteContext } from '../write-context';

@Injectable()
export class RecordCore {
  constructor(
    readonly prisma: PrismaService,
    private readonly events: DomainEvents,
    @Inject(ENV) private readonly env: Env,
  ) {}

  publish(effects: Effects, originDeviceId?: string | null) {
    for (const userId of effects.usersChanged) this.events.emit('user.changed', { userId, originDeviceId });
    if (effects.cardsContentChanged.size > 0) {
      this.events.emit('cards.content.changed', { cardIds: [...effects.cardsContentChanged] });
    }
  }

  async bump(ctx: WriteContext, userId = ctx.userId): Promise<bigint> {
    return bumpSeq(this.prisma, ctx.tx, ctx.effects, userId);
  }

  // ───────────────────────────── Emit canonical rows ─────────────────────────────

  emitProfile(ctx: WriteContext, row: Profile) {
    if (row.deletedAt) ctx.out.tombstone('profile', row.id, row.deletedAt);
    else ctx.out.record('profile', this.profileWire(row, ctx));
  }

  private profileWire(row: Profile, _ctx: WriteContext) {
    return profileToWire(row);
  }

  async emitCard(ctx: WriteContext, row: Card) {
    if (row.deletedAt) ctx.out.tombstone('card', row.id, row.deletedAt);
    else ctx.out.record('card', cardToWire(row, { webBaseUrl: this.env.WEB_BASE_URL, linksPaused: await ctx.linksPaused() }));
  }

  emitEvent(ctx: WriteContext, row: Event) {
    if (row.deletedAt) ctx.out.tombstone('event', row.id, row.deletedAt);
    else ctx.out.record('event', eventToWire(row));
  }

  emitConnection(ctx: WriteContext, row: Connection) {
    if (row.deletedAt) ctx.out.tombstone('connection', row.id, row.deletedAt);
    else ctx.out.record('connection', connectionToWire(row));
  }

  emitFollowUp(ctx: WriteContext, row: FollowUp) {
    if (row.deletedAt) ctx.out.tombstone('followUp', row.id, row.deletedAt);
    else ctx.out.record('followUp', followUpToWire(row));
  }

  async emitAny(ctx: WriteContext, type: Exclude<SyncRecordType, 'connectRequest'>, row: unknown) {
    switch (type) {
      case 'profile':
        return this.emitProfile(ctx, row as Profile);
      case 'card':
        return this.emitCard(ctx, row as Card);
      case 'event':
        return this.emitEvent(ctx, row as Event);
      case 'connection':
        return this.emitConnection(ctx, row as Connection);
      case 'followUp':
        return this.emitFollowUp(ctx, row as FollowUp);
    }
  }
}
