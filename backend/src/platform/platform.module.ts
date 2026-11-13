import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { RecordsModule } from '../records/records.module';
import { DevicesController } from './devices/devices.controller';
import { EntitlementsJob } from './jobs/entitlements.job';
import { EventsJob } from './jobs/events.job';
import { JobRunner } from './jobs/job-lock';
import { PurgeJob } from './jobs/purge.job';
import { RemindersJob } from './jobs/reminders.job';
import { AppStoreGateway } from './subscriptions/app-store.gateway';
import { SubscriptionsController } from './subscriptions/subscriptions.controller';
import { SubscriptionsService } from './subscriptions/subscriptions.service';

/**
 * Devices + APNs registration, scheduled jobs (reminders, auto-end events, purge, lapsed
 * entitlements — timers off under NODE_ENV=test, each job runs under a Postgres advisory lock),
 * App Store subscriptions. PushService itself lives in the global PushModule.
 */
@Module({
  imports: [ScheduleModule.forRoot(), RecordsModule],
  controllers: [DevicesController, SubscriptionsController],
  providers: [
    JobRunner,
    RemindersJob,
    EventsJob,
    PurgeJob,
    EntitlementsJob,
    AppStoreGateway,
    SubscriptionsService,
  ],
  exports: [SubscriptionsService],
})
export class PlatformModule {}
