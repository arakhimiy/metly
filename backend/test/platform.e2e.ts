import { randomBytes, randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { EventsJob } from '../src/platform/jobs/events.job';
import { PurgeJob } from '../src/platform/jobs/purge.job';
import { RemindersJob } from '../src/platform/jobs/reminders.job';
import { PrismaService } from '../src/prisma/prisma.service';
import { pushTestSink } from '../src/push/push-test-sink';
import { expectSchema } from './contract';
import {
  card,
  connection,
  createApp,
  event,
  followUp,
  notificationPrefs,
  now,
  profile,
  request,
  resetRateLimits,
  type Session,
  signIn,
} from './helpers';

const apnsToken = () => randomBytes(32).toString('hex');

describe('platform: devices, push and jobs', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => {
    resetRateLimits(app);
    pushTestSink.clear();
  });

  const http = () => request(app.getHttpServer());
  const register = (s: Session, deviceId: string, token: string, timeZone = 'Asia/Tashkent') =>
    http()
      .put(`/v1/me/devices/${deviceId}`)
      .set(s.auth)
      .send({
        deviceId,
        apnsToken: token,
        apnsEnvironment: 'sandbox',
        platform: 'ios',
        appVersion: '1.0 (42)',
        osVersion: '26.1',
        locale: 'en_UZ',
        timeZone,
      });
  const push = (s: Session, changes: Record<string, unknown>) =>
    http().post('/v1/sync/push').set(s.auth).send({ deviceId: 'device-1', changes }).expect(200);
  const pull = (s: Session, since?: string) =>
    http()
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(s.auth);
  const cursorOf = async (s: Session) => (await pull(s).expect(200)).body.cursor as string;

  /** A signed-in user with a profile and one registered device. */
  const user = async (prefs: Record<string, unknown> = {}) => {
    const s = await signIn(app);
    await http()
      .put('/v1/me/profile')
      .set(s.auth)
      .send(profile({ notificationPrefs: { ...notificationPrefs, ...prefs } }))
      .expect(200);
    const token = apnsToken();
    await register(s, randomUUID(), token).expect(204);
    return { s, token };
  };

  // ───────────────────────────── Devices ─────────────────────────────

  describe('devices', () => {
    it('upserts by (user, deviceId) and moves a token seen under another user', async () => {
      const a = await signIn(app);
      const b = await signIn(app);
      const token = apnsToken();
      await register(a, 'install-1', token).expect(204);
      await register(a, 'install-1', token, 'Europe/Berlin').expect(204);
      let rows = await prisma.device.findMany({ where: { apnsToken: token } });
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({ userId: a.userId, deviceId: 'install-1', timeZone: 'Europe/Berlin', apnsEnvironment: 'sandbox' });

      // Same phone, another account signs in.
      await register(b, 'install-1', token.toUpperCase()).expect(204);
      rows = await prisma.device.findMany({ where: { apnsToken: token } });
      expect(rows.map((r) => r.userId)).toEqual([b.userId]);

      await http().delete('/v1/me/devices/install-1').set(b.auth).expect(204);
      expect(await prisma.device.count({ where: { apnsToken: token } })).toBe(0);
      // Idempotent.
      await http().delete('/v1/me/devices/install-1').set(b.auth).expect(204);
    });

    it('validates the registration', async () => {
      const s = await signIn(app);
      const bad = await register(s, 'install-x', 'not-hex').expect(422);
      expectSchema('Error', bad.body);
      expect(bad.body.details.apnsToken).toBeDefined();
      await register(s, 'install-x', apnsToken(), 'Mars/Olympus').expect(422);
      await http()
        .put('/v1/me/devices/install-x')
        .set(s.auth)
        .send({
          deviceId: 'other',
          apnsToken: apnsToken(),
          apnsEnvironment: 'production',
          platform: 'ios',
          appVersion: '1',
          osVersion: '26',
          locale: 'en',
          timeZone: 'UTC',
        })
        .expect(422);
      await http().put('/v1/me/devices/install-x').send({}).expect(401);
    });
  });

  // ───────────────────────────── Follow-up reminders ─────────────────────────────

  describe('follow-up reminders', () => {
    it('pushes once per dueAt with the app category, collapse id and deep link, without a seq bump', async () => {
      const { s, token } = await user();
      const person = connection({ fullName: 'Sardor Rashidov', telegram: '@sardor' });
      const due = followUp({ connectionId: person.id, title: 'Send the deck', channel: 'telegram', dueAt: now(-60_000) });
      await push(s, { connections: [person], followUps: [due] });
      const cursor = await cursorOf(s);

      const jobs = app.get(RemindersJob);
      await jobs.runOnce();
      const sent = pushTestSink.forUser(s.userId);
      expect(sent).toHaveLength(1);
      expect(sent[0]!.token).toBe(token);
      expect(sent[0]!.environment).toBe('sandbox');
      expect(sent[0]!.headers).toMatchObject({
        'apns-topic': 'app.tanishly.ios',
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'apns-collapse-id': `followup.${due.id.toUpperCase()}`,
      });
      expect(sent[0]!.payload).toEqual({
        aps: {
          alert: { title: 'Follow up with Sardor Rashidov', body: 'Send the deck' },
          sound: 'default',
          category: 'FOLLOW_UP_TELEGRAM',
          'thread-id': 'follow-ups',
        },
        type: 'followup_due',
        followUpId: due.id,
        connectionId: person.id,
        followUpID: due.id.toUpperCase(),
        link: `tanishly://reminder/${due.id.toUpperCase()}`,
      });
      const stored = await prisma.followUp.findUniqueOrThrow({ where: { id: due.id } });
      expect(stored.remindedForDueAt?.toISOString()).toBe(due.dueAt);

      // Once per dueAt.
      await jobs.runOnce();
      expect(pushTestSink.forUser(s.userId)).toHaveLength(1);
      // Server-internal: the follow-up did not change for sync.
      const delta = await pull(s, cursor).expect(200);
      expect(delta.body.changes.followUps).toEqual([]);

      // Moving the due date re-arms it.
      await push(s, { followUps: [{ ...due, dueAt: now(-30_000), updatedAt: now(1000) }] });
      await jobs.runOnce();
      expect(pushTestSink.forUser(s.userId)).toHaveLength(2);
    });

    it('uses the plain category without a channel value, skips done, old and opted-out reminders', async () => {
      const { s } = await user();
      const person = connection({ telegram: '', email: '' });
      const noValue = followUp({ connectionId: person.id, channel: 'email', title: 'Email the offer', dueAt: now(-1000) });
      const done = followUp({ dueAt: now(-1000), isDone: true, completedAt: now() });
      const ancient = followUp({ dueAt: now(-2 * 86_400_000) });
      const future = followUp({ dueAt: now(3_600_000) });
      await push(s, { connections: [person], followUps: [noValue, done, ancient, future] });
      await app.get(RemindersJob).runOnce();
      const sent = pushTestSink.forUser(s.userId);
      expect(sent.map((p) => p.payload.followUpId)).toEqual([noValue.id]);
      expect((sent[0]!.payload.aps as Record<string, unknown>).category).toBe('FOLLOW_UP');

      const off = await user({ followUpReminders: false });
      await push(off.s, { followUps: [followUp({ dueAt: now(-1000) })] });
      await app.get(RemindersJob).runOnce();
      expect(pushTestSink.forUser(off.s.userId)).toEqual([]);
    });

    it('removes a device whose token APNs reports as Unregistered', async () => {
      const { s, token } = await user();
      pushTestSink.respond(token, { status: 410, reason: 'Unregistered' });
      await push(s, { followUps: [followUp({ dueAt: now(-1000) })] });
      await app.get(RemindersJob).runOnce();
      expect(pushTestSink.forUser(s.userId)).toHaveLength(1);
      expect(await prisma.device.count({ where: { userId: s.userId } })).toBe(0);
    });

    it('sends nothing to Telegram-delivery users without a linked chat but falls back to push', async () => {
      // delivery = telegramBot while no chat is linked (telegramLinked is server-owned → false).
      const { s } = await user({ delivery: 'telegramBot' });
      await push(s, { followUps: [followUp({ dueAt: now(-1000) })] });
      await app.get(RemindersJob).runOnce();
      expect(pushTestSink.forUser(s.userId)).toHaveLength(1);
    });
  });

  // ───────────────────────────── Auto-end events ─────────────────────────────

  describe('auto-end events', () => {
    it('ends an event after its last local day, syncs it and sends the summary once', async () => {
      const { s } = await user();
      const e = event({ name: 'ICT Week', startDate: '2026-01-08T04:00:00.000Z', endDate: '2026-01-10T10:00:00.000Z' });
      const met = [connection({ eventId: e.id }), connection({ eventId: e.id })];
      await push(s, { events: [e], connections: met });
      const cursor = await cursorOf(s);
      const jobs = app.get(EventsJob);

      // 23:00 in Tashkent (UTC+5): the day is not over yet.
      await jobs.runOnce(new Date('2026-01-10T18:00:00.000Z'));
      expect((await prisma.event.findUniqueOrThrow({ where: { id: e.id } })).status).toBe('active');

      const at = new Date('2026-01-10T19:00:05.000Z');
      await jobs.runOnce(at);
      const delta = await pull(s, cursor).expect(200);
      expectSchema('SyncPullResponse', delta.body);
      expect(delta.body.changes.events).toHaveLength(1);
      expect(delta.body.changes.events[0]).toMatchObject({ id: e.id, status: 'ended', endedAt: '2026-01-10T18:59:59.999Z' });
      // Never older than the stored edit, so devices apply it.
      expect(Date.parse(delta.body.changes.events[0].updatedAt)).toBeGreaterThanOrEqual(Date.parse(e.updatedAt));

      const sent = pushTestSink.forUser(s.userId);
      expect(sent).toHaveLength(1);
      expect(sent[0]!.payload).toMatchObject({
        type: 'event_summary',
        eventId: e.id,
        aps: { alert: { title: 'ICT Week wrapped up', body: expect.stringContaining('You met 2 people') } },
      });
      // Summaries are quiet.
      expect((sent[0]!.payload.aps as Record<string, unknown>).sound).toBeUndefined();

      await jobs.runOnce(new Date(at.getTime() + 60_000));
      expect(pushTestSink.forUser(s.userId)).toHaveLength(1);
    });

    it('uses the owner’s latest device time zone and respects eventSummary', async () => {
      const s = await signIn(app);
      await http()
        .put('/v1/me/profile')
        .set(s.auth)
        .send(profile({ notificationPrefs: { ...notificationPrefs, eventSummary: false } }))
        .expect(200);
      await register(s, 'ny-phone', apnsToken(), 'America/New_York').expect(204);
      const e = event({ startDate: '2026-02-01T15:00:00.000Z', endDate: '2026-02-01T15:00:00.000Z' });
      await push(s, { events: [e] });
      const jobs = app.get(EventsJob);
      // 23:30 in New York: still that day there (although it is the next day in Tashkent).
      await jobs.runOnce(new Date('2026-02-02T04:30:00.000Z'));
      expect((await prisma.event.findUniqueOrThrow({ where: { id: e.id } })).status).toBe('active');
      await jobs.runOnce(new Date('2026-02-02T05:00:01.000Z'));
      const row = await prisma.event.findUniqueOrThrow({ where: { id: e.id } });
      expect(row.status).toBe('ended');
      expect(row.endedAt?.toISOString()).toBe('2026-02-02T04:59:59.999Z');
      expect(row.summarySentAt).not.toBeNull();
      expect(pushTestSink.forUser(s.userId)).toEqual([]);
    });
  });

  // ───────────────────────────── Tombstone purge ─────────────────────────────

  describe('tombstone purge', () => {
    it('hard-deletes old tombstones, keeps the slug and expires older cursors', async () => {
      const s = await signIn(app);
      const c = card();
      const stored = await push(s, { profile: profile(), cards: [c] });
      const slug = stored.body.records.cards[0].slug as string;
      const before = await cursorOf(s);
      await push(s, { tombstones: [{ type: 'card', id: c.id, deletedAt: now(1000) }] });
      const after = await cursorOf(s);
      const tombstoneSeq = (await prisma.card.findUniqueOrThrow({ where: { id: c.id } })).seq;
      await prisma.card.update({ where: { id: c.id }, data: { deletedAt: new Date(Date.now() - 91 * 86_400_000) } });

      const idemKey = `old-${randomUUID()}`;
      await prisma.idempotencyRecord.create({
        data: { scope: `u:${s.userId}`, key: idemKey, requestHash: 'x', status: 200, createdAt: new Date(Date.now() - 25 * 3_600_000) },
      });

      const result = await app.get(PurgeJob).runOnce();
      expect(result?.tombstones.cards).toBeGreaterThanOrEqual(1);
      expect(await prisma.card.findUnique({ where: { id: c.id } })).toBeNull();
      expect(await prisma.slug.findUnique({ where: { slug } })).not.toBeNull();
      const u = await prisma.user.findUniqueOrThrow({ where: { id: s.userId } });
      expect(u.tombstoneFloorSeq).toBe(tombstoneSeq);
      expect(await prisma.idempotencyRecord.findUnique({ where: { scope_key: { scope: `u:${s.userId}`, key: idemKey } } })).toBeNull();

      const expired = await pull(s, before).expect(410);
      expect(expired.body.code).toBe('cursor_expired');
      await pull(s, after).expect(200);
    });

    it('keeps recent tombstones', async () => {
      const s = await signIn(app);
      const c = card();
      await push(s, { cards: [c] });
      await push(s, { tombstones: [{ type: 'card', id: c.id, deletedAt: now(1000) }] });
      await app.get(PurgeJob).runOnce();
      expect(await prisma.card.findUnique({ where: { id: c.id } })).not.toBeNull();
      expect((await prisma.user.findUniqueOrThrow({ where: { id: s.userId } })).tombstoneFloorSeq).toBe(0n);
    });
  });

  // ───────────────────────────── Telegram without configuration ─────────────────────────────

  describe('telegram (not configured)', () => {
    it('answers 503', async () => {
      const s = await signIn(app);
      const res = await http().post('/v1/integrations/telegram/link').set(s.auth).expect(503);
      expectSchema('Error', res.body);
      expect(res.body.code).toBe('service_unavailable');
      await http().post('/v1/integrations/telegram/webhook').send({ update_id: 1 }).expect(503);
    });
  });
});
