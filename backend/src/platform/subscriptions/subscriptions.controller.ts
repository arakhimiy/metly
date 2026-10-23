import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { NoRateLimit } from '../../common/rate-limit';
import { type AuthedUser, CurrentUser, Public } from '../../common/request';
import { SubscriptionsService } from './subscriptions.service';

@Controller('v1')
export class SubscriptionsController {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  /** StoreKit 2 `Transaction.jwsRepresentation` → Entitlement. */
  @Post('subscriptions/verify')
  @HttpCode(200)
  verify(@CurrentUser() user: AuthedUser, @Body() body: unknown) {
    return this.subscriptions.verify(user.id, body);
  }

  /** App Store Server Notifications V2 (URL configured in App Store Connect). Authenticated by its JWS. */
  @Post('webhooks/app-store')
  @Public()
  @NoRateLimit()
  @HttpCode(200)
  async appStore(@Body() body: unknown) {
    await this.subscriptions.handleNotification(body);
  }
}
