import { Inject, Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { DomainEvents } from '../common/domain-events';
import { minutes } from '../common/time';
import { ENV, type Env } from '../config/env';
import { StorageService } from './storage/storage.service';
import { UploadsService } from './uploads/uploads.service';

/** Account deletion clean-up of stored objects, and an hourly sweep of abandoned uploads. */
@Injectable()
export class MediaCleanupService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MediaCleanupService.name);
  private timer: NodeJS.Timeout | undefined;

  constructor(
    private readonly events: DomainEvents,
    private readonly storage: StorageService,
    private readonly uploads: UploadsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit() {
    this.events.on('account.deleting', ({ userId }) => this.deleteUserObjects(userId));
    if (this.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => {
      this.uploads.sweepExpired().catch((error: unknown) => this.logger.error({ err: error }, 'upload sweep failed'));
    }, minutes(60));
    this.timer.unref();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** Best effort: raw uploads, public images and exports of the user. Wallet registrations go with the rows. */
  async deleteUserObjects(userId: string): Promise<void> {
    const storage = this.storage.storage;
    if (!storage) return;
    for (const prefix of [`uploads/${userId}/`, `public/${userId}/`, `exports/${userId}/`]) {
      try {
        await storage.deletePrefix(prefix);
      } catch (error) {
        this.logger.error({ err: error, prefix }, 'could not delete stored objects of a deleted account');
      }
    }
  }
}
