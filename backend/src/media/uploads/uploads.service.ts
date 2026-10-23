import { randomUUID } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { randomToken } from '../../common/crypto';
import { iso, minutes } from '../../common/time';
import type { Profile } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { profileToWire, type WireRecord } from '../../records/mappers';
import { RecordsService, type WriteContext } from '../../records/records.service';
import { UUID_PARAM } from '../../records/rest';
import type { ObjectStorage } from '../storage/object-storage';
import { StorageService } from '../storage/storage.service';
import { type ImageKind, processImage, UnsupportedImageError } from './image';

export const MAX_UPLOAD_BYTES = 5_000_000;
export const UPLOAD_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/heic'] as const;
/** Lifetime of the presigned PUT. */
export const TICKET_TTL_SECONDS = 15 * 60;
/** A slow upload that started just before the ticket expired may still be committed this long after. */
const COMMIT_GRACE_MS = minutes(15);
const PUBLIC_CACHE_CONTROL = 'public, max-age=31536000, immutable';

const imageField = (kind: ImageKind) => (kind === 'photo' ? 'photoUrl' : 'logoUrl');

@Injectable()
export class UploadsService {
  private readonly logger = new Logger(UploadsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly storage: StorageService,
  ) {}

  private async liveProfile(userId: string): Promise<Profile | null> {
    const profile = await this.prisma.profile.findUnique({ where: { userId } });
    return profile && !profile.deletedAt ? profile : null;
  }

  /** `POST /v1/me/profile/{kind}/upload` — validated by the caller (type 415, size 413). */
  async ticket(userId: string, kind: ImageKind, contentType: string, byteSize: number) {
    const storage = this.storage.require();
    const uploadId = randomUUID();
    const objectKey = `uploads/${userId}/${uploadId}`;
    const expiresAt = new Date(Date.now() + TICKET_TTL_SECONDS * 1000);
    const uploadUrl = await storage.presignPut(objectKey, { contentType, contentLength: byteSize, expiresInSeconds: TICKET_TTL_SECONDS });
    await this.prisma.upload.create({ data: { id: uploadId, userId, kind, objectKey, contentType, byteSize, expiresAt } });
    return {
      uploadId,
      uploadUrl,
      method: 'PUT' as const,
      headers: { 'Content-Type': contentType },
      expiresAt: iso(expiresAt),
      maxBytes: MAX_UPLOAD_BYTES,
    };
  }

  /** `PUT /v1/me/profile/{kind}` — re-encodes the upload and attaches it to the profile. */
  async commit(userId: string, kind: ImageKind, uploadId: string): Promise<WireRecord> {
    const storage = this.storage.require();
    const profile = await this.liveProfile(userId);
    if (!profile) throw ApiError.notFound('Set up your profile first.');
    const upload = UUID_PARAM.test(uploadId) ? await this.prisma.upload.findUnique({ where: { id: uploadId.toLowerCase() } }) : null;
    if (!upload || upload.userId !== userId || upload.kind !== kind) throw ApiError.notFound('This upload doesn’t exist.');
    // A retried commit after success answers with the current profile.
    if (upload.committedAt) return profileToWire(profile);
    if (upload.expiresAt.getTime() + COMMIT_GRACE_MS < Date.now()) throw ApiError.gone('This upload expired. Upload the image again.');

    const head = await storage.headObject(upload.objectKey);
    if (!head) throw ApiError.badRequest('The image hasn’t been uploaded yet.');
    if (head.size > MAX_UPLOAD_BYTES) {
      await this.discard(storage, upload.objectKey);
      throw new ApiError(413, 'payload_too_large', `Images can be at most ${MAX_UPLOAD_BYTES / 1_000_000} MB.`);
    }
    const raw = await storage.getObject(upload.objectKey);
    if (!raw) throw ApiError.badRequest('The image hasn’t been uploaded yet.');

    let processed;
    try {
      processed = await processImage(raw, kind);
    } catch (error) {
      if (!(error instanceof UnsupportedImageError)) throw error;
      await this.discard(storage, upload.objectKey);
      throw new ApiError(415, 'unsupported_media_type', error.message);
    }

    const publicKey = `public/${userId}/${kind}-${randomToken(12)}.${processed.extension}`;
    await storage.putObject(publicKey, processed.body, { contentType: processed.contentType, cacheControl: PUBLIC_CACHE_CONTROL });
    const url = storage.publicUrl(publicKey);

    let outcome: { row: Profile; previous: string | null } | null;
    try {
      ({ result: outcome } = await this.records.write(userId, async (ctx) => {
        // Claim the upload; a concurrent commit of the same upload loses here.
        const claimed = await ctx.tx.upload.updateMany({ where: { id: upload.id, committedAt: null }, data: { committedAt: new Date() } });
        if (claimed.count === 0) return null;
        return this.setImage(ctx, kind, url);
      }));
    } catch (error) {
      await this.discard(storage, publicKey);
      throw error;
    }
    await this.discard(storage, upload.objectKey);
    if (!outcome) {
      await this.discard(storage, publicKey);
      const current = await this.liveProfile(userId);
      if (!current) throw ApiError.notFound('Set up your profile first.');
      return profileToWire(current);
    }
    await this.discardPublic(storage, userId, outcome.previous);
    return profileToWire(outcome.row);
  }

  /** `DELETE /v1/me/profile/{kind}`. */
  async remove(userId: string, kind: ImageKind): Promise<WireRecord> {
    const profile = await this.liveProfile(userId);
    if (!profile) throw ApiError.notFound('Set up your profile first.');
    if (!profile[imageField(kind)]) return profileToWire(profile);
    const { result } = await this.records.write(userId, (ctx) => this.setImage(ctx, kind, null));
    if (this.storage.storage) await this.discardPublic(this.storage.storage, userId, result.previous);
    return profileToWire(result.row);
  }

  /**
   * Sets photoUrl / logoUrl (seq bump, pages + Wallet passes republished). A photo also becomes the
   * server-owned `avatarUrl` of every live connection other users hold of this person.
   */
  private async setImage(ctx: WriteContext, kind: ImageKind, url: string | null): Promise<{ row: Profile; previous: string | null }> {
    const { tx, userId } = ctx;
    const holders =
      kind === 'photo'
        ? (
            await tx.connection.findMany({
              where: { remoteUserId: userId, deletedAt: null, NOT: { userId } },
              select: { userId: true },
              distinct: ['userId'],
            })
          ).map((c) => c.userId)
        : [];
    // Records of several users are written: lock them all, in id order, before the first seq bump.
    await this.prisma.lockUsers(tx, [userId, ...holders]);

    const current = await tx.profile.findUnique({ where: { userId } });
    if (!current || current.deletedAt) throw ApiError.notFound('Set up your profile first.');
    const previous = current[imageField(kind)];
    ctx.effects.usersChanged.add(userId);
    const seq = await this.prisma.nextSeq(tx, userId);
    const row = await tx.profile.update({ where: { userId }, data: { [imageField(kind)]: url, seq } });
    this.records.emitProfile(ctx, row);
    await this.records.touchAllCards(ctx, { republish: true, bumpSeq: false });

    if (holders.length > 0) {
      const connections = await tx.connection.findMany({
        where: { remoteUserId: userId, deletedAt: null, userId: { in: holders } },
        select: { id: true, userId: true, avatarUrl: true },
      });
      for (const connection of connections) {
        if (connection.avatarUrl === url) continue;
        const ownerSeq = await this.prisma.nextSeq(tx, connection.userId);
        await tx.connection.update({ where: { id: connection.id }, data: { avatarUrl: url, seq: ownerSeq } });
        ctx.effects.usersChanged.add(connection.userId);
      }
    }
    return { row, previous };
  }

  /** Deletes a previous public image, only if it is one of this user's objects. */
  private async discardPublic(storage: ObjectStorage, userId: string, url: string | null) {
    if (!url) return;
    const key = storage.keyFromPublicUrl(url);
    if (key?.startsWith(`public/${userId}/`)) await this.discard(storage, key);
  }

  private async discard(storage: ObjectStorage, key: string) {
    try {
      await storage.deleteObject(key);
    } catch (error) {
      this.logger.warn({ err: error, key }, 'could not delete object');
    }
  }

  /** Expired, never-committed uploads: delete the raw object and the row. Returns how many. */
  async sweepExpired(now = new Date()): Promise<number> {
    const storage = this.storage.storage;
    if (!storage) return 0;
    const stale = await this.prisma.upload.findMany({
      where: { committedAt: null, expiresAt: { lt: new Date(now.getTime() - COMMIT_GRACE_MS - minutes(60)) } },
      take: 500,
    });
    for (const upload of stale) {
      await this.discard(storage, upload.objectKey);
      await this.prisma.upload.delete({ where: { id: upload.id } }).catch(() => undefined);
    }
    // Committed rows have served their purpose after a day.
    await this.prisma.upload.deleteMany({ where: { committedAt: { lt: new Date(now.getTime() - minutes(24 * 60)) } } });
    return stale.length;
  }
}
