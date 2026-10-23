import { Body, Controller, Delete, Headers, HttpCode, Inject, Post } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { safeEqual } from '../../common/crypto';
import { NoRateLimit } from '../../common/rate-limit';
import { type AuthedUser, CurrentUser, Public } from '../../common/request';
import { ENV, type Env } from '../../config/env';
import { type TelegramUpdate, TelegramService } from './telegram.service';

@Controller('v1/integrations/telegram')
export class TelegramController {
  constructor(
    private readonly telegram: TelegramService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  @Post('link')
  @HttpCode(200)
  link(@CurrentUser() user: AuthedUser) {
    return this.telegram.createLink(user.id);
  }

  @Delete('link')
  @HttpCode(204)
  async unlink(@CurrentUser() user: AuthedUser) {
    await this.telegram.unlink(user.id);
  }

  /**
   * Bot webhook (`setWebhook` with `secret_token` = TELEGRAM_WEBHOOK_SECRET). Authenticated by the
   * `X-Telegram-Bot-Api-Secret-Token` header; answers 200 to everything it accepted so Telegram
   * does not redeliver.
   */
  @Post('webhook')
  @Public()
  @NoRateLimit()
  @HttpCode(200)
  async webhook(@Headers('x-telegram-bot-api-secret-token') secret: string | undefined, @Body() body: unknown) {
    const expected = this.env.TELEGRAM_WEBHOOK_SECRET;
    if (!expected || !this.telegram.isConfigured) throw ApiError.unavailable('Telegram reminders are not available right now.');
    if (!secret || !safeEqual(secret, expected)) throw ApiError.unauthorized('Invalid webhook secret.');
    if (body && typeof body === 'object') await this.telegram.handleUpdate(body as TelegramUpdate);
    return { ok: true };
  }
}
