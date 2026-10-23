import { Body, Controller, Delete, Get, HttpCode, Inject, Param, Post, Put } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { type AuthedUser, CurrentUser } from '../common/request';
import { days, iso } from '../common/time';
import { parse } from '../common/validate';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
import { cardToWire } from './mappers';
import { RecordsService } from './records.service';
import { pathUuid, restRecord, withPathId } from './rest';
import { type CardDesign, CardIn, uuid } from './wire';

const ReorderBody = z.object({ cardIds: z.array(uuid).max(500) });
const DuplicateBody = z.object({ newCardId: uuid, name: z.string().min(1).max(40) });

@Controller('v1/cards')
export class CardsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  private async page(userId: string) {
    const [cards, profile] = await Promise.all([
      this.prisma.card.findMany({ where: { userId, deletedAt: null }, orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }] }),
      this.prisma.profile.findUnique({ where: { userId }, select: { linksPaused: true } }),
    ]);
    const ctx = { webBaseUrl: this.env.WEB_BASE_URL, linksPaused: profile?.linksPaused ?? false };
    return { items: cards.map((c) => cardToWire(c, ctx)) };
  }

  @Get()
  list(@CurrentUser() user: AuthedUser) {
    return this.page(user.id);
  }

  /** Index in `cardIds` = sortOrder. Unknown ids are ignored. */
  @Put('order')
  async reorder(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    const { cardIds } = parse(ReorderBody, body);
    await this.records.write(user.id, async (ctx) => {
      const now = new Date();
      for (const [index, id] of cardIds.entries()) {
        const card = await ctx.tx.card.findFirst({ where: { id, userId: user.id, deletedAt: null } });
        if (!card || card.sortOrder === index) continue;
        const row = await ctx.tx.card.update({
          where: { id },
          data: { sortOrder: index, updatedAt: card.updatedAt > now ? card.updatedAt : now, seq: await this.prisma.nextSeq(ctx.tx, user.id) },
        });
        ctx.effects.usersChanged.add(user.id);
        await this.records.emitCard(ctx, row);
      }
      return { status: 'applied' as const };
    });
    return this.page(user.id);
  }

  @Get(':cardId')
  async get(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string) {
    const card = await this.prisma.card.findFirst({ where: { id: pathUuid(cardId, 'cardId'), userId: user.id, deletedAt: null } });
    if (!card) throw ApiError.notFound('Card not found.');
    const profile = await this.prisma.profile.findUnique({ where: { userId: user.id }, select: { linksPaused: true } });
    return cardToWire(card, { webBaseUrl: this.env.WEB_BASE_URL, linksPaused: profile?.linksPaused ?? false });
  }

  @Put(':cardId')
  put(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string, @Body() body: unknown) {
    return this.upsert(user.id, pathUuid(cardId, 'cardId'), body);
  }

  /** Same as PUT; exists so the app can surface ALERT_PUBLISH_FAILED immediately. */
  @Post(':cardId/publish')
  @HttpCode(200)
  publish(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string, @Body() body: unknown) {
    return this.upsert(user.id, pathUuid(cardId, 'cardId'), body);
  }

  private async upsert(userId: string, id: string, body: unknown) {
    const incoming = parse(CardIn, withPathId(id, body));
    const { result, out } = await this.records.write(userId, (ctx) => this.records.upsertCard(ctx, incoming));
    return restRecord('card', id, result, out);
  }

  /** The link and QR stop working (`status: deleted`); the slug is never reused. */
  @Delete(':cardId')
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string) {
    const id = pathUuid(cardId, 'cardId');
    const card = await this.prisma.card.findFirst({ where: { id, userId: user.id } });
    if (!card || card.deletedAt) return;
    const now = new Date();
    const deletedAt = card.updatedAt > now ? card.updatedAt : now;
    await this.records.write(user.id, (ctx) => this.records.applyTombstone(ctx, { type: 'card', id, deletedAt }));
  }

  @Post(':cardId/duplicate')
  @HttpCode(201)
  async duplicate(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string, @Body() body: unknown) {
    const { newCardId, name } = parse(DuplicateBody, body);
    const source = await this.prisma.card.findFirst({ where: { id: pathUuid(cardId, 'cardId'), userId: user.id, deletedAt: null } });
    if (!source) throw ApiError.notFound('Card not found.');
    const last = await this.prisma.card.aggregate({ where: { userId: user.id, deletedAt: null }, _max: { sortOrder: true } });
    const now = new Date();
    const copy = CardIn.parse({
      id: newCardId,
      name,
      sortOrder: (last._max.sortOrder ?? 0) + 1,
      design: source.design as CardDesign,
      createdAt: iso(now),
      updatedAt: iso(now),
    });
    const { result, out } = await this.records.write(user.id, (ctx) => this.records.upsertCard(ctx, copy));
    return restRecord('card', newCardId, result, out);
  }

  @Get(':cardId/stats')
  async stats(@CurrentUser() user: AuthedUser, @Param('cardId') cardId: string) {
    const card = await this.prisma.card.findFirst({ where: { id: pathUuid(cardId, 'cardId'), userId: user.id, deletedAt: null } });
    if (!card) throw ApiError.notFound('Card not found.');
    const now = new Date();
    const newConnectionsThisWeek = await this.prisma.connection.count({
      where: { userId: user.id, deletedAt: null, createdAt: { gte: new Date(now.getTime() - days(7)) } },
    });
    return {
      cardId: card.id,
      views: card.views,
      saves: card.saves,
      shareBacks: card.shareBacks,
      scans: card.scans,
      newConnectionsThisWeek,
      asOf: iso(now),
    };
  }
}
