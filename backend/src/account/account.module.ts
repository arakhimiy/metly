import { Module } from '@nestjs/common';
import { SubscriptionsCoreModule } from '../subscriptions/subscriptions-core.module';
import { AccountController } from './account.controller';

@Module({ imports: [SubscriptionsCoreModule], controllers: [AccountController] })
export class AccountModule {}
