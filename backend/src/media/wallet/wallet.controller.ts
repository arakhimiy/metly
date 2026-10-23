import { Controller, Get, Param, Res } from '@nestjs/common';
import type { Response } from 'express';
import { ApiError } from '../../common/api-error';
import { type AuthedUser, CurrentUser } from '../../common/request';
import { PrismaService } from '../../prisma/prisma.service';
import { pathUuid } from '../../records/rest';
import { PKPASS_CONTENT_TYPE, WalletService } from './wallet.service';

@Controller('v1/cards')
export class WalletController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
  ) {}

  /** `GET /v1/cards/{cardId}/wallet-pass` — the owner's signed `.pkpass` for a live card. */
  @Get(':cardId/wallet-pass')
  async pass(@CurrentUser() user: AuthedUser, @Param('cardId') cardIdParam: string, @Res() res: Response) {
    const cardId = pathUuid(cardIdParam, 'cardId');
    const card = await this.prisma.card.findUnique({ where: { id: cardId } });
    if (!card || card.userId !== user.id || card.deletedAt) throw ApiError.notFound('Card not found.');
    const profile = await this.prisma.profile.findUnique({ where: { userId: user.id } });
    if (!profile || profile.deletedAt) throw ApiError.notFound('Set up your profile first.');
    this.wallet.assertConfigured();
    const body = await this.wallet.render(card, profile);
    res.status(200);
    res.setHeader('Content-Type', PKPASS_CONTENT_TYPE);
    res.setHeader('Content-Disposition', `attachment; filename="metly-${card.slug ?? 'card'}.pkpass"`);
    res.setHeader('Last-Modified', card.contentUpdatedAt.toUTCString());
    res.setHeader('Cache-Control', 'no-store');
    res.send(body);
  }
}
