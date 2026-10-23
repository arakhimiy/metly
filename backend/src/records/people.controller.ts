import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { decodeOffset, encodeOffset } from '../common/cursor';
import { type AuthedUser, CurrentUser } from '../common/request';
import { iso } from '../common/time';
import { parse } from '../common/validate';
import type { SyncRecordType } from './wire';
import { PrismaService } from '../prisma/prisma.service';
import { connectionToWire, eventToWire, followUpToWire } from './mappers';
import { RecordsService } from './records.service';
import { pathUuid, restRecord, withPathId } from './rest';
import { ConnectionIn, EventIn, FollowUpIn, timestamp } from './wire';

function limitOf(raw: string | undefined, fallback = 100) {
  const n = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(n) ? Math.min(500, Math.max(1, n)) : fallback;
}

function pageOf<T>(rows: T[], offset: number, limit: number, map: (row: T) => unknown) {
  const hasMore = rows.length > limit;
  return { items: rows.slice(0, limit).map(map), nextCursor: hasMore ? encodeOffset(offset + limit) : null };
}

/** Deletes by tombstoning now (or at the record's updatedAt when that is later, so LWW holds). */
async function deleteNow(records: RecordsService, prisma: PrismaService, userId: string, type: Exclude<SyncRecordType, 'connectRequest' | 'profile'>, id: string) {
  const delegate = { card: prisma.card, event: prisma.event, connection: prisma.connection, followUp: prisma.followUp }[type] as unknown as {
    findFirst(args: unknown): Promise<{ updatedAt: Date; deletedAt: Date | null } | null>;
  };
  const row = await delegate.findFirst({ where: { id, userId } });
  if (!row || row.deletedAt) return;
  const now = new Date();
  await records.write(userId, (ctx) => records.applyTombstone(ctx, { type, id, deletedAt: row.updatedAt > now ? row.updatedAt : now }));
}

@Controller('v1/connections')
export class ConnectionsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
  ) {}

  /** Paged list for tooling and exports (the app syncs via /v1/sync). */
  @Get()
  async list(@CurrentUser() user: AuthedUser, @Query('updatedSince') updatedSince?: string, @Query('cursor') cursor?: string, @Query('limit') limit?: string) {
    const since = updatedSince ? parse(timestamp, updatedSince) : undefined;
    const offset = decodeOffset(cursor);
    const take = limitOf(limit);
    const rows = await this.prisma.connection.findMany({
      where: { userId: user.id, deletedAt: null, ...(since ? { updatedAt: { gte: since } } : {}) },
      orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      skip: offset,
      take: take + 1,
    });
    return pageOf(rows, offset, take, connectionToWire);
  }

  @Put(':connectionId')
  async put(@CurrentUser() user: AuthedUser, @Param('connectionId') connectionId: string, @Body() body: unknown) {
    const id = pathUuid(connectionId, 'connectionId');
    const incoming = parse(ConnectionIn, withPathId(id, body));
    const { result, out } = await this.records.write(user.id, (ctx) => this.records.upsertConnection(ctx, incoming));
    return restRecord('connection', id, result, out);
  }

  /** One-sided remove ("They keep the card you shared"); cascades to its follow-ups. */
  @Delete(':connectionId')
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthedUser, @Param('connectionId') connectionId: string) {
    await deleteNow(this.records, this.prisma, user.id, 'connection', pathUuid(connectionId, 'connectionId'));
  }
}

const BulkBody = z.object({ items: z.array(FollowUpIn).max(500) });

@Controller('v1/followups')
export class FollowUpsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
  ) {}

  @Get()
  async list(@CurrentUser() user: AuthedUser, @Query('cursor') cursor?: string, @Query('limit') limit?: string) {
    const offset = decodeOffset(cursor);
    const take = limitOf(limit);
    const rows = await this.prisma.followUp.findMany({
      where: { userId: user.id, deletedAt: null },
      orderBy: [{ dueAt: 'asc' }, { id: 'asc' }],
      skip: offset,
      take: take + 1,
    });
    return pageOf(rows, offset, take, followUpToWire);
  }

  /** "Follow up with everyone I haven't yet" — all-or-nothing against the Free limit. */
  @Post('bulk')
  @HttpCode(200)
  async bulk(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    const { items } = parse(BulkBody, body);
    const { out } = await this.records.write(user.id, async (ctx) => {
      await this.records.bulkUpsertFollowUps(ctx, items);
      return null;
    });
    return { items: items.map((i) => out.get('followUp', i.id)).filter(Boolean) };
  }

  @Put(':followUpId')
  async put(@CurrentUser() user: AuthedUser, @Param('followUpId') followUpId: string, @Body() body: unknown) {
    const id = pathUuid(followUpId, 'followUpId');
    const incoming = parse(FollowUpIn, withPathId(id, body));
    const { result, out } = await this.records.write(user.id, (ctx) => this.records.upsertFollowUp(ctx, incoming));
    return restRecord('followUp', id, result, out);
  }

  @Delete(':followUpId')
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthedUser, @Param('followUpId') followUpId: string) {
    await deleteNow(this.records, this.prisma, user.id, 'followUp', pathUuid(followUpId, 'followUpId'));
  }
}

@Controller('v1/events')
export class EventsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
  ) {}

  @Get()
  async list(@CurrentUser() user: AuthedUser) {
    const rows = await this.prisma.event.findMany({ where: { userId: user.id, deletedAt: null }, orderBy: [{ startDate: 'desc' }, { id: 'asc' }] });
    return { items: rows.map(eventToWire) };
  }

  @Put(':eventId')
  async put(@CurrentUser() user: AuthedUser, @Param('eventId') eventId: string, @Body() body: unknown) {
    const id = pathUuid(eventId, 'eventId');
    const incoming = parse(EventIn, withPathId(id, body));
    const { result, out } = await this.records.write(user.id, (ctx) => this.records.upsertEvent(ctx, incoming));
    return restRecord('event', id, result, out);
  }

  /** Tombstone; connections keep the event name in their context but lose `eventId`. */
  @Delete(':eventId')
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthedUser, @Param('eventId') eventId: string) {
    await deleteNow(this.records, this.prisma, user.id, 'event', pathUuid(eventId, 'eventId'));
  }

  @Post(':eventId/end')
  @HttpCode(200)
  end(@CurrentUser() user: AuthedUser, @Param('eventId') eventId: string) {
    return this.setStatus(user.id, pathUuid(eventId, 'eventId'), 'ended');
  }

  @Post(':eventId/resume')
  @HttpCode(200)
  resume(@CurrentUser() user: AuthedUser, @Param('eventId') eventId: string) {
    return this.setStatus(user.id, pathUuid(eventId, 'eventId'), 'active');
  }

  private async setStatus(userId: string, id: string, status: 'active' | 'ended') {
    const event = await this.prisma.event.findFirst({ where: { id, userId, deletedAt: null } });
    if (!event) throw ApiError.notFound('Event not found.');
    const now = new Date();
    const updatedAt = event.updatedAt > now ? new Date(event.updatedAt.getTime() + 1) : now;
    const incoming = EventIn.parse({
      ...eventToWire(event),
      status,
      endedAt: status === 'ended' ? iso(now) : null,
      updatedAt: iso(updatedAt),
    });
    const { result, out } = await this.records.write(userId, (ctx) => this.records.upsertEvent(ctx, incoming));
    return restRecord('event', id, result, out);
  }

  @Get(':eventId/summary')
  async summary(@CurrentUser() user: AuthedUser, @Param('eventId') eventId: string) {
    const id = pathUuid(eventId, 'eventId');
    const event = await this.prisma.event.findFirst({ where: { id, userId: user.id, deletedAt: null } });
    if (!event) throw ApiError.notFound('Event not found.');
    const people = await this.prisma.connection.findMany({
      where: { userId: user.id, eventId: id, deletedAt: null },
      select: { id: true, note: true },
    });
    const openFollowUps = await this.prisma.followUp.count({
      where: { userId: user.id, deletedAt: null, isDone: false, connectionId: { in: people.map((p) => p.id) } },
    });
    const unnoted = people.filter((p) => p.note.trim().length === 0).map((p) => p.id);
    return {
      eventId: id,
      people: people.length,
      withNotes: people.length - unnoted.length,
      openFollowUps,
      unnotedConnectionIds: unnoted,
      startedAt: iso(event.startDate),
      ...(event.endedAt ? { endedAt: iso(event.endedAt) } : {}),
    };
  }
}
