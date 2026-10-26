/**
 * The few object-storage operations Tanishly needs (S3 / Cloudflare R2 / Backblaze B2, or memory in tests).
 *
 * Key layout (one bucket):
 * - `uploads/{userId}/{uploadId}` — raw client uploads (private, presigned PUT, deleted on commit);
 * - `public/{userId}/{kind}-{random}.{ext}` — re-encoded profile photos / logos, served from
 *   `S3_PUBLIC_BASE_URL` (the only prefix that may be publicly readable);
 * - `exports/{userId}/{random}.zip` — data exports (private, presigned GET for 7 days).
 */
export interface ObjectStorage {
  putObject(key: string, body: Buffer, options: { contentType: string; cacheControl?: string }): Promise<void>;
  /** null when the object does not exist. */
  getObject(key: string): Promise<Buffer | null>;
  /** null when the object does not exist. */
  headObject(key: string): Promise<{ size: number; contentType?: string } | null>;
  /** Succeeds when the object does not exist. */
  deleteObject(key: string): Promise<void>;
  /** Deletes every object under `prefix`; returns how many were deleted. */
  deletePrefix(prefix: string): Promise<number>;
  /** Presigned PUT that only accepts exactly `contentType` and `contentLength` bytes. */
  presignPut(key: string, options: { contentType: string; contentLength: number; expiresInSeconds: number }): Promise<string>;
  presignGet(key: string, options: { expiresInSeconds: number; downloadName?: string }): Promise<string>;
  /** Public (CDN) URL of a key under `public/`. */
  publicUrl(key: string): string;
  /** Inverse of publicUrl for URLs this storage issued; null for anything else. */
  keyFromPublicUrl(url: string): string | null;
}

export function joinUrl(base: string, key: string): string {
  return `${base.replace(/\/+$/, '')}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

export function keyFromUrl(base: string, url: string): string | null {
  const prefix = `${base.replace(/\/+$/, '')}/`;
  if (!url.startsWith(prefix)) return null;
  try {
    return url
      .slice(prefix.length)
      .split('/')
      .map((part) => decodeURIComponent(part))
      .join('/');
  } catch {
    return null;
  }
}
