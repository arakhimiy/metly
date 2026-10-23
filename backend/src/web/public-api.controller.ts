import { Body, Controller, Delete, Get, Headers, HttpCode, Param, Post, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { z } from 'zod';
import { ApiError } from '../common/api-error';
import { RateLimit } from '../common/rate-limit';
import { clientIp, Public } from '../common/request';
import { parse } from '../common/validate';
import { UUID_PARAM } from '../records/rest';
import { PublicCardService } from './public-card.service';
import { ShareBackService } from './shareback.service';
import { WebStatsService } from './web-stats.service';

const WebEventBody = z.object({
  type: z.enum(['view', 'save', 'copy_phone', 'copy_email', 'telegram_open', 'get_app']),
  platform: z.enum(['ios', 'android', 'inapp', 'desktop']),
  source: z.enum(['qr', 'link']).nullish(),
  referrer: z.string().max(2048).nullish(),
});

/** JSON endpoints used by the metly.link page (openapi tag "Public web"). */
@Controller('api/public')
@Public()
export class PublicApiController {
  constructor(
    private readonly cards: PublicCardService,
    private readonly shareBacks: ShareBackService,
    private readonly stats: WebStatsService,
  ) {}

  @Get('cards/:slug')
  @RateLimit('publicCard')
  async card(@Param('slug') slug: string, @Res({ passthrough: true }) res: Response) {
    const resolved = await this.cards.resolve(slug);
    if (resolved.status === 'unknown') throw ApiError.notFound('Card not found.');
    res.setHeader('Cache-Control', 'public, max-age=60');
    return this.cards.wire(resolved);
  }

  @Post('cards/:slug/shareback')
  @HttpCode(201)
  @RateLimit('shareBackPerIp')
  async shareBack(@Param('slug') slug: string, @Body() body: unknown) {
    const resolved = await this.cards.resolve(slug);
    if (resolved.status === 'unknown' || resolved.status === 'deleted') throw ApiError.notFound('Card not found.');
    const profile = resolved.status === 'available' ? resolved.profile : null;
    return this.shareBacks.receive(resolved.card, profile, body);
  }

  /** Analytics beacon; always 202 (unknown, paused and bot traffic is accepted and ignored). */
  @Post('cards/:slug/events')
  @HttpCode(202)
  @RateLimit('analytics')
  async event(@Param('slug') slug: string, @Body() body: unknown, @Req() req: Request): Promise<void> {
    const input = parse(WebEventBody, body);
    const resolved = await this.cards.resolve(slug);
    if (resolved.status !== 'available') return;
    // "Get the app" is counted by the redirect that records the deferred click.
    if (input.type === 'get_app') return;
    await this.stats.record(
      resolved.card,
      { type: input.type, source: input.source ?? null },
      { ip: clientIp(req), userAgent: req.get('user-agent') ?? '' },
    );
  }

  /** "Remove my contact" — idempotent; unknown ids are a no-op (discarded share-backs have none). */
  @Delete('sharebacks/:shareBackId')
  @HttpCode(204)
  async removeShareBack(@Param('shareBackId') id: string, @Headers('x-removal-token') token: string | undefined): Promise<void> {
    if (!UUID_PARAM.test(id)) return;
    await this.shareBacks.remove(id.toLowerCase(), token);
  }
}
