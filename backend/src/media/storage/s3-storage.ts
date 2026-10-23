import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
  S3ServiceException,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { joinUrl, keyFromUrl, type ObjectStorage } from './object-storage';

export interface S3StorageConfig {
  endpoint?: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  publicBaseUrl: string;
}

const isNotFound = (error: unknown) =>
  error instanceof S3ServiceException && (error.name === 'NotFound' || error.name === 'NoSuchKey' || error.$metadata.httpStatusCode === 404);

/** S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO). */
export class S3Storage implements ObjectStorage {
  private readonly client: S3Client;

  constructor(private readonly config: S3StorageConfig) {
    this.client = new S3Client({
      region: config.region,
      ...(config.endpoint ? { endpoint: config.endpoint, forcePathStyle: true } : {}),
      credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
      // R2 / B2 do not implement every flexible-checksum header; only send them where S3 requires one.
      requestChecksumCalculation: 'WHEN_REQUIRED',
      responseChecksumValidation: 'WHEN_REQUIRED',
    });
  }

  async putObject(key: string, body: Buffer, options: { contentType: string; cacheControl?: string }): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.config.bucket,
        Key: key,
        Body: body,
        ContentType: options.contentType,
        ContentLength: body.length,
        ...(options.cacheControl ? { CacheControl: options.cacheControl } : {}),
      }),
    );
  }

  async getObject(key: string): Promise<Buffer | null> {
    try {
      const result = await this.client.send(new GetObjectCommand({ Bucket: this.config.bucket, Key: key }));
      if (!result.Body) return null;
      return Buffer.from(await result.Body.transformToByteArray());
    } catch (error) {
      if (isNotFound(error)) return null;
      throw error;
    }
  }

  async headObject(key: string): Promise<{ size: number; contentType?: string } | null> {
    try {
      const result = await this.client.send(new HeadObjectCommand({ Bucket: this.config.bucket, Key: key }));
      return { size: result.ContentLength ?? 0, ...(result.ContentType ? { contentType: result.ContentType } : {}) };
    } catch (error) {
      if (isNotFound(error)) return null;
      throw error;
    }
  }

  async deleteObject(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.config.bucket, Key: key }));
  }

  async deletePrefix(prefix: string): Promise<number> {
    let deleted = 0;
    let token: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({ Bucket: this.config.bucket, Prefix: prefix, ContinuationToken: token, MaxKeys: 1000 }),
      );
      const keys = (page.Contents ?? []).map((o) => o.Key).filter((k): k is string => Boolean(k));
      if (keys.length > 0) {
        await this.client.send(
          new DeleteObjectsCommand({ Bucket: this.config.bucket, Delete: { Objects: keys.map((Key) => ({ Key })), Quiet: true } }),
        );
        deleted += keys.length;
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
    return deleted;
  }

  presignPut(key: string, options: { contentType: string; contentLength: number; expiresInSeconds: number }): Promise<string> {
    const command = new PutObjectCommand({
      Bucket: this.config.bucket,
      Key: key,
      ContentType: options.contentType,
      ContentLength: options.contentLength,
    });
    // Signing Content-Length makes the store refuse any other size (no oversized uploads).
    return getSignedUrl(this.client, command, {
      expiresIn: options.expiresInSeconds,
      signableHeaders: new Set(['content-type', 'content-length']),
    });
  }

  presignGet(key: string, options: { expiresInSeconds: number; downloadName?: string }): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: this.config.bucket,
      Key: key,
      ...(options.downloadName ? { ResponseContentDisposition: `attachment; filename="${options.downloadName}"` } : {}),
    });
    return getSignedUrl(this.client, command, { expiresIn: options.expiresInSeconds });
  }

  publicUrl(key: string): string {
    return joinUrl(this.config.publicBaseUrl, key);
  }

  keyFromPublicUrl(url: string): string | null {
    return keyFromUrl(this.config.publicBaseUrl, url);
  }
}
