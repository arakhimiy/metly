import { Inject, Injectable, Logger, type OnApplicationShutdown } from '@nestjs/common';
import { ENV, type Env } from '../config/env';
import { type Lang, langFromLocale } from '../i18n/lang';
import { type PushTextRef, renderPush } from '../i18n/messages';
import { PrismaService } from '../prisma/prisma.service';
import { DEFAULT_NOTIFICATION_PREFS, NotificationPrefs } from '../records/wire';
import { type ApnsEnvironment, ApnsTransport, type PushTransport } from './apns.transport';
import { allowedByPrefs, apnsHeaders, apnsPayload } from './push-payload';
import { TestSinkTransport } from './push-test-sink';

/** Push types (docs/api/README.md § Push notifications); each is gated by a notificationPrefs toggle. */
export type PushType =
  | 'connect_request'
  | 'connect_result'
  | 'shareback_received'
  | 'card_saved'
  | 'followup_due'
  | 'event_summary'
  | 'weekly_summary'
  | 'product_news';

export interface PushMessage {
  type: PushType;
  /**
   * Catalog message and its parameters (src/i18n/messages.ts), e.g.
   * `{ id: 'followUpDue', params: { personName, title } }`. Rendered per device in the language of
   * its `devices.locale` (a user's phones may differ).
   */
  text: PushTextRef;
  /** Deep-link ids: connectionId, requestId, followUpId, eventId. Never note text (Lock Screen privacy). */
  data?: Record<string, string>;
  /**
   * `apns-collapse-id`. Follow-up reminders use the app's local notification identifier
   * (`followup.{FOLLOW-UP-ID}`, uppercase) so the push replaces the local fallback instead of doubling.
   */
  collapseId?: string;
  /**
   * Notification category the app registers: `FOLLOW_UP_TELEGRAM` / `_EMAIL` / `_CALL` ("Open …" +
   * "Snooze 1 Day") or `FOLLOW_UP` (snooze only) — FollowUpNotificationCategory.swift; `CONNECT_REQUEST`
   * (Accept + Decline) — ConnectRequestNotificationCategory.swift.
   */
  category?: string;
  threadId?: string;
}

/** APNs reasons that mean the token will never work again: drop the device row. */
const DEAD_TOKEN = new Set(['Unregistered', 'BadDeviceToken', 'ExpiredToken']);

/**
 * Sends a push to every registered device of a user, honouring their notificationPrefs, with the
 * text rendered in each device's own language (`devices.locale`, see `langFromLocale`).
 * Frozen public API — callers across modules depend on `notify`.
 *
 * `notify` never throws: delivery is best-effort and must not fail the caller's request. Without APNs
 * credentials (APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY) it logs at debug and returns. Under
 * `NODE_ENV=test` every push goes to `pushTestSink` (src/push/push-test-sink.ts) instead of APNs.
 */
@Injectable()
export class PushService implements OnApplicationShutdown {
  protected readonly logger = new Logger(PushService.name);
  private readonly transport: PushTransport | undefined;

  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {
    if (env.NODE_ENV === 'test') {
      this.transport = new TestSinkTransport();
    } else if (env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY) {
      this.transport = new ApnsTransport({ keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, privateKey: env.APNS_PRIVATE_KEY });
    }
  }

  get isConfigured(): boolean {
    return this.transport !== undefined;
  }

  async notify(userId: string, message: PushMessage): Promise<void> {
    try {
      await this.deliver(userId, message);
    } catch (error) {
      this.logger.error({ err: error, userId, type: message.type }, 'push failed');
    }
  }

  /** The user's effective notification preferences (defaults until a profile exists). */
  async prefs(userId: string): Promise<NotificationPrefs> {
    const profile = await this.prisma.profile.findUnique({ where: { userId }, select: { notificationPrefs: true, deletedAt: true } });
    const parsed = profile && !profile.deletedAt ? NotificationPrefs.safeParse(profile.notificationPrefs) : undefined;
    return parsed?.success ? parsed.data : DEFAULT_NOTIFICATION_PREFS;
  }

  private async deliver(userId: string, message: PushMessage): Promise<void> {
    const transport = this.transport;
    if (!transport) {
      this.logger.debug({ userId, type: message.type }, 'push skipped (APNs not configured)');
      return;
    }
    if (!allowedByPrefs(message.type, await this.prefs(userId))) {
      this.logger.debug({ userId, type: message.type }, 'push skipped (notification preference off)');
      return;
    }
    const devices = await this.prisma.device.findMany({ where: { userId } });
    if (devices.length === 0) return;

    const headers = apnsHeaders(this.env.APNS_TOPIC, message);
    const { text, ...rest } = message;
    const payloads = new Map<Lang, Record<string, unknown>>();
    const payloadFor = (lang: Lang) => {
      let payload = payloads.get(lang);
      if (!payload) {
        payload = apnsPayload({ ...rest, ...renderPush(text, lang) });
        payloads.set(lang, payload);
      }
      return payload;
    };
    await Promise.all(
      devices.map(async (device) => {
        const environment: ApnsEnvironment = device.apnsEnvironment === 'sandbox' ? 'sandbox' : 'production';
        const payload = payloadFor(langFromLocale(device.locale));
        try {
          const result = await transport.send(
            { token: device.apnsToken, environment, headers, payload },
            { userId, deviceId: device.deviceId },
          );
          if (result.status === 200) return;
          if ((result.status === 410 || result.status === 400) && DEAD_TOKEN.has(result.reason ?? '')) {
            // Only the row that still holds this token (it may have been re-registered meanwhile).
            await this.prisma.device.deleteMany({ where: { userId, deviceId: device.deviceId, apnsToken: device.apnsToken } });
            this.logger.log({ userId, deviceId: device.deviceId, reason: result.reason }, 'removed dead APNs token');
            return;
          }
          this.logger.warn({ userId, deviceId: device.deviceId, status: result.status, reason: result.reason }, 'APNs rejected push');
        } catch (error) {
          this.logger.warn({ err: error, userId, deviceId: device.deviceId }, 'APNs request failed');
        }
      }),
    );
  }

  async onApplicationShutdown(): Promise<void> {
    await this.transport?.close();
  }
}
