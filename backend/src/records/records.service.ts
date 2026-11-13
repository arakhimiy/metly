// The facade over record writes: runs a write transaction and delegates each record type to its
// writer (writers/*). Sync, controllers, connect, web and media call this; its API is unchanged.
import { Injectable } from '@nestjs/common';
import type { Card, Connection, Event, FollowUp, Profile } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import type { ApplyResult, ChangeSet } from './changes';
import type { ConnectionIn, ContactEntry, CardIn, EventIn, FollowUpIn, ProfileIn, SyncRecordType, TombstoneIn } from './wire';
import { type Effects, WriteContext } from './write-context';
import { CardWriter } from './writers/card.writer';
import { ConnectionWriter } from './writers/connection.writer';
import { EventWriter } from './writers/event.writer';
import { FollowUpWriter } from './writers/follow-up.writer';
import { ProfileWriter } from './writers/profile.writer';
import { RecordCore } from './writers/record-core';
import { TombstoneWriter } from './writers/tombstones';

// Kept here so existing `from '../records/records.service'` imports keep compiling.
export { Effects, WriteContext } from './write-context';

@Injectable()
export class RecordsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly core: RecordCore,
    private readonly profiles: ProfileWriter,
    private readonly cards: CardWriter,
    private readonly events: EventWriter,
    private readonly connections: ConnectionWriter,
    private readonly followUps: FollowUpWriter,
    private readonly tombstones: TombstoneWriter,
  ) {}

  /** Runs `fn` in a transaction and publishes its side effects once it committed. */
  async write<T>(userId: string, fn: (ctx: WriteContext) => Promise<T>, originDeviceId?: string | null): Promise<{ result: T; out: ChangeSet }> {
    let ctx!: WriteContext;
    const result = await this.prisma.write(async (tx) => {
      ctx = new WriteContext(tx, userId);
      return fn(ctx);
    });
    this.publish(ctx.effects, originDeviceId);
    return { result, out: ctx.out };
  }

  publish(effects: Effects, originDeviceId?: string | null) {
    this.core.publish(effects, originDeviceId);
  }

  // ───────────────────────────── Emit canonical rows ─────────────────────────────

  emitProfile(ctx: WriteContext, row: Profile) {
    this.core.emitProfile(ctx, row);
  }

  async emitCard(ctx: WriteContext, row: Card) {
    await this.core.emitCard(ctx, row);
  }

  emitEvent(ctx: WriteContext, row: Event) {
    this.core.emitEvent(ctx, row);
  }

  emitConnection(ctx: WriteContext, row: Connection) {
    this.core.emitConnection(ctx, row);
  }

  emitFollowUp(ctx: WriteContext, row: FollowUp) {
    this.core.emitFollowUp(ctx, row);
  }

  // ───────────────────────────── Profile ─────────────────────────────

  upsertProfile(ctx: WriteContext, incoming: ProfileIn): Promise<ApplyResult> {
    return this.profiles.upsertProfile(ctx, incoming);
  }

  /**
   * Cards derive isPaused and their public content from the profile: bump their seq so devices pull
   * the new isPaused, and their contentUpdatedAt so pages and Wallet passes refresh.
   */
  touchAllCards(ctx: WriteContext, opts: { republish: boolean; bumpSeq: boolean }) {
    return this.cards.touchAllCards(ctx, opts);
  }

  // ───────────────────────────── Cards ─────────────────────────────

  upsertCard(ctx: WriteContext, incoming: CardIn): Promise<ApplyResult> {
    return this.cards.upsertCard(ctx, incoming);
  }

  // ───────────────────────────── Events ─────────────────────────────

  upsertEvent(ctx: WriteContext, incoming: EventIn): Promise<ApplyResult> {
    return this.events.upsertEvent(ctx, incoming);
  }

  // ───────────────────────────── Connections ─────────────────────────────

  /** The list a connection write stores (see `ConnectionWriter.incomingConnectionContacts`). */
  incomingConnectionContacts(incoming: ConnectionIn, stored: ContactEntry[]): ContactEntry[] {
    return this.connections.incomingConnectionContacts(incoming, stored);
  }

  connectionData(incoming: ConnectionIn, contacts: ContactEntry[]) {
    return this.connections.connectionData(incoming, contacts);
  }

  upsertConnection(ctx: WriteContext, incoming: ConnectionIn): Promise<ApplyResult> {
    return this.connections.upsertConnection(ctx, incoming);
  }

  // ───────────────────────────── Follow-ups ─────────────────────────────

  upsertFollowUp(ctx: WriteContext, incoming: FollowUpIn): Promise<ApplyResult> {
    return this.followUps.upsertFollowUp(ctx, incoming);
  }

  resolveConnectionAlias(ctx: WriteContext, connectionId: string): Promise<string> {
    return this.followUps.resolveConnectionAlias(ctx, connectionId);
  }

  /** Bulk create-or-update, all-or-nothing against the Free open follow-up limit. */
  bulkUpsertFollowUps(ctx: WriteContext, items: FollowUpIn[]): Promise<void> {
    return this.followUps.bulkUpsertFollowUps(ctx, items);
  }

  // ───────────────────────────── Tombstones ─────────────────────────────

  applyTombstone(ctx: WriteContext, t: TombstoneIn): Promise<ApplyResult> {
    return this.tombstones.applyTombstone(ctx, t);
  }

  cascadeDelete(ctx: WriteContext, type: SyncRecordType, id: string, deletedAt: Date) {
    return this.tombstones.cascadeDelete(ctx, type, id, deletedAt);
  }
}
