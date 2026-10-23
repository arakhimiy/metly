import { randomBytes } from 'node:crypto';
import { joinUrl, keyFromUrl, type ObjectStorage } from './object-storage';

export interface StoredObject {
  body: Buffer;
  contentType: string;
  cacheControl?: string;
}

/**
 * In-memory storage for tests (`NODE_ENV=test` + `METLY_TEST_STORAGE=memory`). Presigned URLs point at
 * `https://storage.metly.test/{key}`; tests "upload" with `putObject(keyFromPresignedUrl(url), …)`.
 */
export class MemoryStorage implements ObjectStorage {
  static readonly PRESIGN_BASE = 'https://storage.metly.test';
  readonly objects = new Map<string, StoredObject>();
  readonly presigned = new Map<string, { key: string; contentType?: string; contentLength?: number }>();

  constructor(private readonly publicBaseUrl: string) {}

  async putObject(key: string, body: Buffer, options: { contentType: string; cacheControl?: string }): Promise<void> {
    this.objects.set(key, { body: Buffer.from(body), contentType: options.contentType, ...(options.cacheControl ? { cacheControl: options.cacheControl } : {}) });
  }

  async getObject(key: string): Promise<Buffer | null> {
    return this.objects.get(key)?.body ?? null;
  }

  async headObject(key: string): Promise<{ size: number; contentType?: string } | null> {
    const object = this.objects.get(key);
    return object ? { size: object.body.length, contentType: object.contentType } : null;
  }

  async deleteObject(key: string): Promise<void> {
    this.objects.delete(key);
  }

  async deletePrefix(prefix: string): Promise<number> {
    let deleted = 0;
    for (const key of [...this.objects.keys()]) {
      if (key.startsWith(prefix)) {
        this.objects.delete(key);
        deleted += 1;
      }
    }
    return deleted;
  }

  async presignPut(key: string, options: { contentType: string; contentLength: number; expiresInSeconds: number }): Promise<string> {
    const url = `${joinUrl(MemoryStorage.PRESIGN_BASE, key)}?X-Amz-Expires=${options.expiresInSeconds}&sig=${randomBytes(8).toString('hex')}`;
    this.presigned.set(url, { key, contentType: options.contentType, contentLength: options.contentLength });
    return url;
  }

  async presignGet(key: string, options: { expiresInSeconds: number; downloadName?: string }): Promise<string> {
    const url = `${joinUrl(MemoryStorage.PRESIGN_BASE, key)}?X-Amz-Expires=${options.expiresInSeconds}&sig=${randomBytes(8).toString('hex')}`;
    this.presigned.set(url, { key });
    return url;
  }

  publicUrl(key: string): string {
    return joinUrl(this.publicBaseUrl, key);
  }

  keyFromPublicUrl(url: string): string | null {
    return keyFromUrl(this.publicBaseUrl, url);
  }

  /** Test helper: the key a presigned URL points at. */
  keyFromPresignedUrl(url: string): string {
    const entry = this.presigned.get(url);
    if (!entry) throw new Error(`Not a presigned URL of this storage: ${url}`);
    return entry.key;
  }
}
