import { Body, Controller, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { RateLimit } from '../common/rate-limit';
import { clientIp, Public } from '../common/request';
import { DeferredLinksService } from './deferred-links.service';

@Controller('v1/deferred-links')
@Public()
export class DeferredLinksController {
  constructor(private readonly deferred: DeferredLinksService) {}

  /** First launch: who shared their card before this install? `{invite: null}` when unsure. */
  @Post('claim')
  @HttpCode(200)
  @RateLimit('deferredClaim')
  claim(@Body() body: unknown, @Req() req: Request) {
    return this.deferred.claim(body, clientIp(req));
  }
}
