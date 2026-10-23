import type { NotificationPrefs } from '../records/wire';
import type { PushMessage, PushType } from './push.service';

/**
 * Which `notificationPrefs` toggle gates each push type (docs/api/README.md § Push notifications).
 *
 * - `followup_due` needs `followUpReminders`, and is sent through APNs only when reminders are not
 *   delivered by the Telegram bot (`delivery == telegramBot` with a linked chat goes to Telegram).
 * - `shareback_received` has no toggle of its own: it is activity on the user's card page, like a
 *   save, so it follows `cardSaved` ("When someone adds you to Contacts").
 */
export function allowedByPrefs(type: PushType, prefs: NotificationPrefs): boolean {
  switch (type) {
    case 'followup_due':
      return prefs.followUpReminders && !(prefs.delivery === 'telegramBot' && prefs.telegramLinked === true);
    case 'event_summary':
      return prefs.eventSummary;
    case 'connect_request':
    case 'connect_result':
      return prefs.connectRequests;
    case 'card_saved':
    case 'shareback_received':
      return prefs.cardSaved;
    case 'weekly_summary':
      return prefs.weeklySummary;
    case 'product_news':
      return prefs.productNews;
  }
}

/** "Summaries arrive quietly, without sound." (Settings › Notifications footer). */
const QUIET: ReadonlySet<PushType> = new Set(['event_summary', 'weekly_summary']);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Keys the app reads besides the contract ids: `followUpID` + `link` (`metly://reminder/{ID}`) on
 * reminders (FollowUpNotificationAction), and `link` (`metly://person/{id}`, `metly://people`) routed
 * through DeepLinkHandler for everything else. Callers' own `link` wins.
 */
export function deepLinkData(data: Record<string, string> = {}): Record<string, string> {
  const out = { ...data };
  const followUpId = data.followUpId;
  if (followUpId && UUID.test(followUpId)) {
    out.followUpID ??= followUpId.toUpperCase();
    out.link ??= `metly://reminder/${followUpId.toUpperCase()}`;
  }
  if (!out.link && data.connectionId && UUID.test(data.connectionId)) out.link = `metly://person/${data.connectionId.toUpperCase()}`;
  if (!out.link && data.requestId) out.link = 'metly://people';
  return out;
}

/** APNs caps alert payloads at 4 KB; titles and bodies are short, but never let one overflow. */
const clip = (value: string, max: number) => (value.length > max ? `${value.slice(0, max - 1)}…` : value);

export function apnsPayload(message: PushMessage): Record<string, unknown> {
  const aps: Record<string, unknown> = {
    alert: { title: clip(message.title, 200), body: clip(message.body, 1000) },
  };
  if (!QUIET.has(message.type)) aps.sound = 'default';
  if (message.category) aps.category = message.category;
  if (message.threadId) aps['thread-id'] = message.threadId;
  return { ...deepLinkData(message.data), aps, type: message.type };
}

export interface ApnsHeaders {
  'apns-topic': string;
  'apns-push-type': 'alert';
  'apns-priority': '10';
  'apns-collapse-id'?: string;
}

export function apnsHeaders(topic: string, message: PushMessage): ApnsHeaders {
  return {
    'apns-topic': topic,
    'apns-push-type': 'alert',
    'apns-priority': '10',
    // apns-collapse-id is limited to 64 bytes.
    ...(message.collapseId ? { 'apns-collapse-id': Buffer.from(message.collapseId).subarray(0, 64).toString() } : {}),
  };
}
