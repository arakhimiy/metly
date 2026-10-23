import { Injectable } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { JobRunner } from './job-lock';
import { JOBS_DISABLED } from './jobs-config';

/** Every 10 minutes: Pro entitlements past expiry without an EXPIRED notification become Free. */
@Injectable()
export class EntitlementsJob {
  constructor(
    private readonly subscriptions: SubscriptionsService,
    private readonly jobs: JobRunner,
  ) {}

  @Cron(CronExpression.EVERY_10_MINUTES, { name: 'lapsed-entitlements', disabled: JOBS_DISABLED, waitForCompletion: true })
  async tick() {
    await this.jobs.tick('lapsed-entitlements', () => this.process(new Date()));
  }

  runOnce(now = new Date()) {
    return this.jobs.run('lapsed-entitlements', () => this.process(now));
  }

  private async process(now: Date) {
    return { expired: await this.subscriptions.expireLapsed(now) };
  }
}
