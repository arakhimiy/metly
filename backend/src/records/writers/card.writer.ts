// Card writes: the LWW upsert with its Free-plan limits, first-write slug allocation, and the
// seq/content touch of every card when the profile they derive from changes.
import { Injectable } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { randomToken } from '../../common/crypto';
import type { Card, Prisma } from '../../generated/prisma/client';
import { EntitlementsService } from '../../subscriptions/entitlements.service';
import type { ApplyResult } from '../changes';
import { slugCandidate, slugStem } from '../slug';
import { type CardDesign, type CardIn, PRO_PALETTES, PRO_TEMPLATES } from '../wire';
import { lww, sameJson, type WriteContext } from '../write-context';
import { RecordCore } from './record-core';

const designUsesPro = (design: CardDesign) => PRO_TEMPLATES.has(design.template) || PRO_PALETTES.has(design.palette);

@Injectable()
export class CardWriter {
  constructor(
    private readonly core: RecordCore,
    private readonly entitlements: EntitlementsService,
  ) {}

  async upsertCard(ctx: WriteContext, incoming: CardIn): Promise<ApplyResult> {
    const { tx, userId } = ctx;
    const existing = await tx.card.findUnique({ where: { id: incoming.id } });
    if (existing && existing.userId !== userId) {
      return { status: 'rejected', error: new ApiError(409, 'conflict', 'This id belongs to another record.') };
    }
    const verdict = lww(existing, incoming.updatedAt);
    if (verdict !== 'apply' && existing) {
      await this.core.emitCard(ctx, existing);
      return { status: 'stale' };
    }
    const live = existing && !existing.deletedAt ? existing : null;
    const plan = await ctx.planFor(this.entitlements);

    if (!live && plan.limits.maxCards !== null) {
      const count = await tx.card.count({ where: { userId, deletedAt: null, NOT: { id: incoming.id } } });
      if (count >= plan.limits.maxCards) {
        return { status: 'rejected', error: ApiError.planLimit('cards', `The Free plan includes ${plan.limits.maxCards} cards.`) };
      }
    }
    const designChanged = !live || !sameJson(live.design, incoming.design);
    if (!plan.pro && designChanged && designUsesPro(incoming.design)) {
      return { status: 'rejected', error: ApiError.proRequired('Editorial and the Ocean and Ember palettes need Nameshake Pro.') };
    }
    if (live?.isReadOnly && (designChanged || live.name !== incoming.name)) {
      return { status: 'rejected', error: ApiError.proRequired('This card is read-only on the Free plan.') };
    }

    const seq = await this.core.bump(ctx);
    const contentChanged = !live || designChanged || live.name !== incoming.name;
    const data = {
      name: incoming.name,
      sortOrder: incoming.sortOrder,
      design: incoming.design as unknown as Prisma.InputJsonValue,
      updatedAt: incoming.updatedAt,
      deletedAt: null,
      seq,
      ...(contentChanged ? { contentUpdatedAt: new Date() } : {}),
    };
    let row: Card;
    if (existing) {
      row = await tx.card.update({ where: { id: existing.id }, data });
      if (!row.slug) row = await this.assignSlug(ctx, row);
    } else {
      row = await tx.card.create({
        data: {
          ...data,
          id: incoming.id,
          userId,
          createdAt: incoming.createdAt,
          passAuthToken: randomToken(24),
          contentUpdatedAt: new Date(),
        },
      });
      row = await this.assignSlug(ctx, row);
    }
    if (contentChanged) ctx.effects.cardsContentChanged.add(row.id);
    await this.core.emitCard(ctx, row);
    return { status: 'applied' };
  }

  /** First accepted write: `{firstname}-{4}`, globally unique and never reused. */
  private async assignSlug(ctx: WriteContext, card: Card): Promise<Card> {
    const profile = await ctx.tx.profile.findUnique({ where: { userId: ctx.userId }, select: { fullName: true } });
    const stem = slugStem(profile?.fullName ?? '');
    for (let attempt = 0; attempt < 20; attempt++) {
      const slug = slugCandidate(stem);
      // ON CONFLICT keeps the transaction usable when the candidate is taken.
      const inserted = await ctx.tx.$executeRaw`INSERT INTO slugs (slug, card_id) VALUES (${slug}, ${card.id}::uuid) ON CONFLICT DO NOTHING`;
      if (inserted === 1) return ctx.tx.card.update({ where: { id: card.id }, data: { slug } });
    }
    throw new Error('Could not allocate a unique slug');
  }

  /**
   * Cards derive isPaused and their public content from the profile: bump their seq so devices pull
   * the new isPaused, and their contentUpdatedAt so pages and Wallet passes refresh.
   */
  async touchAllCards(ctx: WriteContext, opts: { republish: boolean; bumpSeq: boolean }) {
    const cards = await ctx.tx.card.findMany({ where: { userId: ctx.userId, deletedAt: null } });
    for (const card of cards) {
      const data: Prisma.CardUpdateInput = {};
      if (opts.bumpSeq) data.seq = await this.core.bump(ctx);
      if (opts.republish) {
        data.contentUpdatedAt = new Date();
        ctx.effects.cardsContentChanged.add(card.id);
      }
      const row = await ctx.tx.card.update({ where: { id: card.id }, data });
      if (opts.bumpSeq) await this.core.emitCard(ctx, row);
    }
  }
}
