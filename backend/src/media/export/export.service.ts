import { Inject, Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from '@nestjs/common';
import { randomToken } from '../../common/crypto';
import { minutes } from '../../common/time';
import { ENV, type Env } from '../../config/env';
import type { DataExportRequest } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { cardToWire, connectionToWire, eventToWire, followUpToWire, profileToWire } from '../../records/mappers';
import type { ObjectStorage } from '../storage/object-storage';
import { StorageService } from '../storage/storage.service';
import { type ArchiveEntry, connectionsCsv, zip } from './export-archive';

/** Presigned download links live 7 days (the SigV4 maximum). */
export const EXPORT_LINK_TTL_SECONDS = 7 * 24 * 3600;
const RUN_EVERY_MS = minutes(5);
const BATCH = 10;

const escapeHtml = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/**
 * "Download My Data": every 5 minutes one instance (Postgres advisory lock) turns queued
 * `data_export_requests` into a ZIP — the owner's own live records in wire format (incl. private
 * fields and notes), connections.csv and the stored photo/logo — uploads it to `exports/{userId}/`,
 * and emails a 7-day link to the account's stored email through Resend. Without storage or
 * RESEND_API_KEY requests stay queued. The timer is off under NODE_ENV=test; tests call runOnce().
 */
@Injectable()
export class ExportService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ExportService.name);
  private timer: NodeJS.Timeout | undefined;
  private running = false;
  private warnedUnconfigured = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  onModuleInit() {
    if (this.env.NODE_ENV === 'test') return;
    this.timer = setInterval(() => {
      this.runOnce().catch((error: unknown) => this.logger.error({ err: error }, 'data export run failed'));
    }, RUN_EVERY_MS);
    this.timer.unref();
  }

  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }

  /** Processes up to one batch of queued requests; returns how many were completed. */
  async runOnce(): Promise<number> {
    const storage = this.storage.storage;
    if (!storage || !this.env.RESEND_API_KEY) {
      if (!this.warnedUnconfigured) {
        this.warnedUnconfigured = true;
        this.logger.warn('data exports stay queued: S3 storage or RESEND_API_KEY is not configured');
      }
      return 0;
    }
    if (this.running) return 0;
    this.running = true;
    try {
      // Transaction-scoped advisory lock: released on commit, so a crashed run never leaves it held.
      return await this.prisma.$transaction(
        async (tx) => {
          const [row] = await tx.$queryRaw<{ locked: boolean }[]>`SELECT pg_try_advisory_xact_lock(hashtext('metly:data-export')) AS locked`;
          if (!row?.locked) return 0;
          const pending = await this.prisma.dataExportRequest.findMany({ where: { completedAt: null }, orderBy: { requestedAt: 'asc' }, take: BATCH });
          let completed = 0;
          for (const request of pending) {
            try {
              if (await this.process(storage, request)) completed += 1;
            } catch (error) {
              this.logger.error({ err: error, requestId: request.id }, 'data export failed; will retry');
            }
          }
          return completed;
        },
        { maxWait: 10_000, timeout: minutes(30) },
      );
    } finally {
      this.running = false;
    }
  }

  private async process(storage: ObjectStorage, request: DataExportRequest): Promise<boolean> {
    const user = await this.prisma.user.findUnique({ where: { id: request.userId }, select: { id: true, email: true, deletedAt: true } });
    // Only ever the account's own stored email — never an address from elsewhere.
    const email = user && !user.deletedAt ? user.email : null;
    if (!user || !email) {
      this.logger.warn({ requestId: request.id }, 'data export has no account email; closing it');
      await this.prisma.dataExportRequest.update({ where: { id: request.id }, data: { completedAt: new Date() } });
      return false;
    }
    const archive = await this.buildArchive(storage, user.id);
    const key = `exports/${user.id}/${randomToken(16)}.zip`;
    await storage.putObject(key, archive, { contentType: 'application/zip' });
    const url = await storage.presignGet(key, { expiresInSeconds: EXPORT_LINK_TTL_SECONDS, downloadName: 'metly-data.zip' });
    await this.sendEmail(email, url);
    await this.prisma.dataExportRequest.update({ where: { id: request.id }, data: { completedAt: new Date() } });
    this.logger.log({ requestId: request.id, bytes: archive.length }, 'data export delivered');
    return true;
  }

  /** The ZIP for one user (exposed for tests). */
  async buildArchive(storage: ObjectStorage | null, userId: string): Promise<Buffer> {
    const [profile, cards, connections, events, followUps] = await Promise.all([
      this.prisma.profile.findUnique({ where: { userId } }),
      this.prisma.card.findMany({ where: { userId, deletedAt: null }, orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }] }),
      this.prisma.connection.findMany({ where: { userId, deletedAt: null }, orderBy: { createdAt: 'asc' } }),
      this.prisma.event.findMany({ where: { userId, deletedAt: null }, orderBy: { startDate: 'asc' } }),
      this.prisma.followUp.findMany({ where: { userId, deletedAt: null }, orderBy: { dueAt: 'asc' } }),
    ]);
    const liveProfile = profile && !profile.deletedAt ? profile : null;
    const cardContext = { webBaseUrl: this.env.WEB_BASE_URL, linksPaused: liveProfile?.linksPaused ?? false };
    const connectionsWire = connections.map(connectionToWire);
    const json = (value: unknown) => `${JSON.stringify(value, null, 2)}\n`;
    const entries: ArchiveEntry[] = [
      { name: 'profile.json', body: json(liveProfile ? profileToWire(liveProfile) : null) },
      { name: 'cards.json', body: json(cards.map((c) => cardToWire(c, cardContext))) },
      { name: 'connections.json', body: json(connectionsWire) },
      { name: 'events.json', body: json(events.map(eventToWire)) },
      { name: 'followups.json', body: json(followUps.map(followUpToWire)) },
      { name: 'connections.csv', body: connectionsCsv(connectionsWire) },
    ];
    if (liveProfile && storage) {
      for (const [name, url] of [
        ['photo', liveProfile.photoUrl],
        ['logo', liveProfile.logoUrl],
      ] as const) {
        const key = url ? storage.keyFromPublicUrl(url) : null;
        if (!key?.startsWith(`public/${userId}/`)) continue;
        const body = await storage.getObject(key);
        const extension = key.split('.').pop() ?? 'jpg';
        if (body) entries.push({ name: `images/${name}.${extension}`, body });
      }
    }
    return zip(entries);
  }

  private async sendEmail(to: string, url: string): Promise<void> {
    const text = [
      'Your Tanishly data export is ready.',
      '',
      `Download it within 7 days: ${url}`,
      '',
      'The ZIP contains your profile, cards, connections (JSON and CSV), events, follow-ups and images.',
      'If you didn’t ask for this, you can ignore this email.',
    ].join('\n');
    const html = `<p>Your Tanishly data export is ready.</p><p><a href="${escapeHtml(url)}">Download your data</a> (the link works for 7 days).</p><p>The ZIP contains your profile, cards, connections (JSON and CSV), events, follow-ups and images.</p><p>If you didn’t ask for this, you can ignore this email.</p>`;
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: this.env.MAIL_FROM, to: [to], subject: 'Your Tanishly data export', text, html }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Resend answered ${response.status}`);
  }
}
