import { Module } from '@nestjs/common';
import { EntitlementsService } from './entitlements.service';

/** Plan and limits, needed by every writer; the App Store integration lives in SubscriptionsModule. */
@Module({ providers: [EntitlementsService], exports: [EntitlementsService] })
export class SubscriptionsCoreModule {}
