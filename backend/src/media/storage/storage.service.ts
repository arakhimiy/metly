import { Inject, Injectable, Logger } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { ENV, type Env } from '../../config/env';
import { MemoryStorage } from './memory-storage';
import type { ObjectStorage } from './object-storage';
import { S3Storage } from './s3-storage';

/**
 * Selects the object storage once at boot:
 * - `NODE_ENV=test` and `METLY_TEST_STORAGE=memory` → in-memory (tests only; ignored elsewhere);
 * - S3_BUCKET + S3_ACCESS_KEY_ID + S3_SECRET_ACCESS_KEY + S3_PUBLIC_BASE_URL → S3-compatible;
 * - otherwise none: uploads answer 503 and exports stay queued.
 */
export function createStorage(env: Env, source: NodeJS.ProcessEnv = process.env): ObjectStorage | null {
  if (env.NODE_ENV === 'test' && source.METLY_TEST_STORAGE === 'memory') {
    return new MemoryStorage(env.S3_PUBLIC_BASE_URL ?? 'https://cdn.metly.test');
  }
  if (env.S3_BUCKET && env.S3_ACCESS_KEY_ID && env.S3_SECRET_ACCESS_KEY && env.S3_PUBLIC_BASE_URL) {
    return new S3Storage({
      ...(env.S3_ENDPOINT ? { endpoint: env.S3_ENDPOINT } : {}),
      region: env.S3_REGION,
      bucket: env.S3_BUCKET,
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
      publicBaseUrl: env.S3_PUBLIC_BASE_URL,
    });
  }
  return null;
}

@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  readonly storage: ObjectStorage | null;

  constructor(@Inject(ENV) env: Env) {
    this.storage = createStorage(env);
    if (!this.storage && env.NODE_ENV !== 'test') this.logger.warn('S3 storage not configured: image uploads return 503, exports stay queued');
  }

  /** The storage, or 503 service_unavailable when none is configured. */
  require(message = 'Image uploads aren’t available right now. Try again later.'): ObjectStorage {
    if (!this.storage) throw ApiError.unavailable(message);
    return this.storage;
  }
}
