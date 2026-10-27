import { describe, expect, it } from 'vitest';
import { DEFAULT_NOTIFICATION_PREFS } from '../records/wire';
import { allowedByPrefs, apnsHeaders, apnsPayload, deepLinkData } from './push-payload';

const ID = '0b6c1d2e-3f40-4a5b-8c6d-7e8f9a0b1c2d';

describe('push payload', () => {
  it('gates each type by its notificationPrefs toggle', () => {
    const all = { ...DEFAULT_NOTIFICATION_PREFS, weeklySummary: true, productNews: true };
    const none = {
      ...all,
      followUpReminders: false,
      eventSummary: false,
      connectRequests: false,
      cardSaved: false,
      weeklySummary: false,
      productNews: false,
    };
    const types = ['connect_request', 'connect_result', 'shareback_received', 'card_saved', 'followup_due', 'event_summary', 'weekly_summary', 'product_news'] as const;
    for (const type of types) {
      expect(allowedByPrefs(type, all)).toBe(true);
      expect(allowedByPrefs(type, none)).toBe(false);
    }
    // Reminders go to the bot instead when it is linked and chosen.
    expect(allowedByPrefs('followup_due', { ...all, delivery: 'telegramBot', telegramLinked: true })).toBe(false);
    expect(allowedByPrefs('followup_due', { ...all, delivery: 'telegramBot', telegramLinked: false })).toBe(true);
  });

  it('adds the deep-link keys the app reads', () => {
    expect(deepLinkData({ followUpId: ID, connectionId: ID })).toEqual({
      followUpId: ID,
      connectionId: ID,
      followUpID: ID.toUpperCase(),
      link: `tanishly://reminder/${ID.toUpperCase()}`,
    });
    expect(deepLinkData({ connectionId: ID }).link).toBe(`tanishly://person/${ID.toUpperCase()}`);
    expect(deepLinkData({ requestId: ID }).link).toBe('tanishly://people');
    expect(deepLinkData({ eventId: ID })).toEqual({ eventId: ID });
    expect(deepLinkData({ connectionId: ID, link: 'tanishly://people' }).link).toBe('tanishly://people');
  });

  it('builds the aps dictionary; summaries are silent; data cannot override aps or type', () => {
    expect(
      apnsPayload({ type: 'connect_request', title: 'Aziza wants to connect', body: 'ICT Week', category: 'C', threadId: 't', data: { requestId: ID, type: 'x', aps: 'y' } }),
    ).toEqual({
      aps: { alert: { title: 'Aziza wants to connect', body: 'ICT Week' }, sound: 'default', category: 'C', 'thread-id': 't' },
      type: 'connect_request',
      requestId: ID,
      link: 'tanishly://people',
    });
    expect(apnsPayload({ type: 'weekly_summary', title: 'Week', body: '3 new' }).aps).toEqual({ alert: { title: 'Week', body: '3 new' } });
    const long = apnsPayload({ type: 'product_news', title: 't', body: 'x'.repeat(5000) });
    expect(((long.aps as { alert: { body: string } }).alert.body).length).toBe(1000);
  });

  it('sets the APNs headers', () => {
    expect(apnsHeaders('app.tanishly.ios', { collapseId: 'followup.X' })).toEqual({
      'apns-topic': 'app.tanishly.ios',
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-collapse-id': 'followup.X',
    });
    expect(apnsHeaders('t', {})).not.toHaveProperty('apns-collapse-id');
  });
});
