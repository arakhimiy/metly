import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { RateLimitStore } from '../src/common/rate-limit';
import { PrismaService } from '../src/prisma/prisma.service';
import { PushService } from '../src/push/push.service';
import { RealtimeService } from '../src/realtime/realtime.service';
import { expectSchema } from './contract';
import { card, connection, createApp, design, event, followUp, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
const BOT = 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';
const FINGERPRINT = { model: 'iPhone17,1', osVersion: '18.1', locale: 'en_UZ', timeZone: 'Asia/Tashkent', preferredLanguages: ['en-US'] };

const allFields = { ...design, visibleFields: ['phone', 'email', 'telegram', 'website', 'linkedin'] };
const ownerFields = [
  { kind: 'phone', value: '+998 90 123 45 67', privacy: 'public' },
  { kind: 'email', value: 'kamola@metly.test', privacy: 'connections' },
  { kind: 'telegram', value: '@kamola_secret', privacy: 'private' },
  { kind: 'website', value: 'tanishly.app', privacy: 'public' },
  { kind: 'linkedin', value: '', privacy: 'public' },
];

let ipCounter = 10;
/** A fresh client address per call, so per-IP budgets and visitor de-duplication stay independent. */
const nextIp = () => `203.0.113.${ipCounter++ % 250}`;

describe('public web', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));
  afterEach(() => vi.restoreAllMocks());

  const http = () => request(app.getHttpServer());
  const push = (s: Session, changes: Record<string, unknown>) =>
    http().post('/v1/sync/push').set(s.auth).send({ deviceId: 'device-1', changes }).expect(200);
  const pull = (s: Session, since?: string) =>
    http()
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(s.auth)
      .expect(200);

  interface Owner {
    session: Session;
    cardId: string;
    slug: string;
  }
  async function owner(overrides: { profile?: Record<string, unknown>; changes?: Record<string, unknown> } = {}): Promise<Owner> {
    const session = await signIn(app);
    const c = card({ design: allFields });
    const res = await push(session, {
      profile: profile({ contactFields: ownerFields, ...overrides.profile }),
      cards: [c],
      ...overrides.changes,
    });
    return { session, cardId: c.id, slug: res.body.records.cards[0].slug };
  }

  const stats = async (o: Owner) => (await http().get(`/v1/cards/${o.cardId}/stats`).set(o.session.auth).expect(200)).body;
  const shareBack = (o: Owner, body: Record<string, unknown>, ip = nextIp()) =>
    http()
      .post(`/api/public/cards/${o.slug}/shareback`)
      .set('X-Forwarded-For', ip)
      .send({ platform: 'ios', ...body });
  const webEvent = (o: Owner, body: Record<string, unknown>, ip: string, ua = IPHONE) =>
    http().post(`/api/public/cards/${o.slug}/events`).set('X-Forwarded-For', ip).set('User-Agent', ua).send(body).expect(202);

  // ───────────────────────────── Public JSON ─────────────────────────────

  describe('GET /api/public/cards/{slug}', () => {
    it('shows only Public ∩ visible fields, without owner.userId or viewer', async () => {
      const o = await owner();
      const res = await http().get(`/api/public/cards/${o.slug.toUpperCase()}`).expect(200);
      expectSchema('PublicCard', res.body);
      expect(res.headers['cache-control']).toBe('public, max-age=60');
      expect(res.body).toMatchObject({
        slug: o.slug,
        status: 'available',
        url: `https://metly.test/c/${o.slug}`,
        cardName: 'Work',
        owner: { fullName: 'Kamola Yusupova', firstName: 'Kamola', jobTitle: 'Product Manager', company: 'Tanishly' },
      });
      expect(res.body.owner.userId).toBeUndefined();
      expect(res.body.viewer).toBeUndefined();
      expect(res.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'website']);
      expect(JSON.stringify(res.body)).not.toContain('kamola@metly.test');
      expect(JSON.stringify(res.body)).not.toContain('kamola_secret');
    });

    it('respects the card’s visibleFields', async () => {
      const session = await signIn(app);
      const c = card({ design: { ...design, visibleFields: ['website'] } });
      const res = await push(session, { profile: profile({ contactFields: ownerFields }), cards: [c] });
      const body = (await http().get(`/api/public/cards/${res.body.records.cards[0].slug}`).expect(200)).body;
      expect(body.fields).toEqual([{ kind: 'website', value: 'tanishly.app', privacy: 'public' }]);
    });

    it('paused → only slug and status', async () => {
      const o = await owner();
      await http().patch('/v1/me/settings').set(o.session.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
      const res = await http().get(`/api/public/cards/${o.slug}`).expect(200);
      expectSchema('PublicCard', res.body);
      expect(res.body).toEqual({ slug: o.slug, status: 'paused' });
    });

    it('deleted → status deleted; unknown or malformed → 404', async () => {
      const o = await owner();
      await http().delete(`/v1/cards/${o.cardId}`).set(o.session.auth).expect(204);
      const res = await http().get(`/api/public/cards/${o.slug}`).expect(200);
      expect(res.body).toEqual({ slug: o.slug, status: 'deleted' });
      const unknown = await http().get('/api/public/cards/nobody-zzzz').expect(404);
      expect(unknown.body.code).toBe('not_found');
      await http().get('/api/public/cards/Bad_Slug!').expect(404);
    });
  });

  // ───────────────────────────── HTML page ─────────────────────────────

  describe('GET /c/{slug}', () => {
    it('renders the card with public fields, CSP nonce, noindex and no app banner without APP_STORE_ID', async () => {
      const o = await owner();
      const res = await http().get(`/c/${o.slug}?src=qr`).set('User-Agent', IPHONE).set('Accept-Language', 'en-US,en;q=0.9').expect(200);
      expect(res.headers['content-type']).toMatch(/^text\/html/);
      expect(res.text).toContain('<html lang="en">');
      const csp = res.headers['content-security-policy'] as string;
      const nonce = /script-src 'nonce-([^']+)'/.exec(csp)?.[1];
      expect(nonce).toBeTruthy();
      expect(csp).toContain("default-src 'none'");
      expect(res.text).toContain(`<script nonce="${nonce}">`);
      expect(res.text).toContain(`<style nonce="${nonce}">`);
      expect(res.text).toContain('<meta name="robots" content="noindex, nofollow">');
      expect(res.text).toContain('property="og:title" content="Kamola Yusupova · Tanishly"');
      expect(res.text).toContain('href="tel:+998901234567"');
      expect(res.text).toContain('href="https://tanishly.app/"');
      expect(res.text).toContain(`href="/c/${o.slug}.vcf"`);
      expect(res.text).toContain('Exchange contacts with Kamola');
      expect(res.text).not.toContain('kamola@metly.test');
      expect(res.text).not.toContain('kamola_secret');
      expect(res.text).not.toContain('apple-itunes-app');
      expect(res.text).not.toContain('/get-app');
      expect(res.text.match(/<script/g)).toHaveLength(1);
    });

    it('escapes a malicious name everywhere', async () => {
      const evil = '<script>alert(1)</script>"><img src=x onerror=alert(2)>';
      const o = await owner({ profile: { fullName: evil, jobTitle: "</title><script>alert('t')</script>", company: '&amp;' } });
      const res = await http().get(`/c/${o.slug}`).set('User-Agent', IPHONE).expect(200);
      expect(res.text).not.toContain('<script>alert');
      expect(res.text).not.toContain('<img src=x');
      expect(res.text).not.toContain("</title><script>");
      expect(res.text).toContain('&lt;script&gt;alert(1)&lt;/script&gt;&quot;&gt;&lt;img src=x onerror=alert(2)&gt;');
      expect(res.text).toContain('&amp;amp;');
      expect(res.text.match(/<script/g)).toHaveLength(1);
    });

    it('speaks Uzbek by default, Russian or English from Accept-Language; ?lang= wins', async () => {
      const o = await owner();
      const uz = await http().get(`/c/${o.slug}`).set('User-Agent', IPHONE).expect(200);
      expect(uz.headers.vary).toMatch(/Accept-Language/);
      expect(uz.text).toContain('<html lang="uz">');
      expect(uz.text).toContain('<meta property="og:locale" content="uz_UZ">');
      expect(uz.text).toContain('Kontaktlarga saqlash');
      expect(uz.text).toContain('Kamola bilan kontakt almashish');
      expect(uz.text).toContain('Buni faqat Kamola ko‘radi.');
      expect(uz.text).not.toContain('Save to Contacts');

      const ru = await http().get(`/c/${o.slug}`).set('User-Agent', IPHONE).set('Accept-Language', 'ru-RU,ru;q=0.9,en;q=0.8').expect(200);
      expect(ru.text).toContain('<html lang="ru">');
      expect(ru.text).toContain('Сохранить в контакты');
      expect(ru.text).toContain('Обменяться контактами');
      expect(ru.text).toContain('Это увидит только Kamola.');
      expect(ru.text).toContain('<span class="label">телефон</span>');
      expect(ru.text).not.toContain('Save to Contacts');

      const en = await http().get(`/c/${o.slug}`).set('User-Agent', IPHONE).set('Accept-Language', 'en-GB,en;q=0.9').expect(200);
      expect(en.text).toContain('<html lang="en">');
      expect(en.text).toContain('Save to Contacts');

      const forced = await http().get(`/c/${o.slug}?src=qr&lang=ru`).set('User-Agent', IPHONE).set('Accept-Language', 'en-US').expect(200);
      expect(forced.text).toContain('<html lang="ru">');
      const unknown = await http().get(`/c/${o.slug}?lang=de`).set('User-Agent', IPHONE).set('Accept-Language', 'de-DE').expect(200);
      expect(unknown.text).toContain('<html lang="uz">');

      // The script's texts come from the server as escaped JSON; the one nonce'd script stays constant.
      const attr = /data-t="([^"]*)"/.exec(ru.text)?.[1] ?? '';
      const unescaped = attr.replace(/&(quot|#39|#96|lt|gt|amp);/g, (_m, e: string) => ({ quot: '"', '#39': "'", '#96': '`', lt: '<', gt: '>', amp: '&' })[e]!);
      expect(JSON.parse(unescaped)).toMatchObject({ sending: 'Отправка…', offline: 'Похоже, нет подключения к интернету. Попробуйте ещё раз.' });
      expect(ru.text.match(/<script/g)).toHaveLength(1);
      const script = ru.text.slice(ru.text.indexOf('<script'));
      expect(script).not.toMatch(/Sending|Try again|Link Copied/);
    });

    it('paused → 200 unavailable page without personal data; deleted → 410; unknown → 404', async () => {
      const paused = await owner();
      await http().patch('/v1/me/settings').set(paused.session.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
      const p = await http().get(`/c/${paused.slug}?lang=en`).expect(200);
      expect(p.text).toContain('This card isn’t available right now.');
      expect(p.text).not.toContain('Kamola');
      expect(p.text).not.toContain('+998');

      const deleted = await owner();
      await http().delete(`/v1/cards/${deleted.cardId}`).set(deleted.session.auth).expect(204);
      const d = await http().get(`/c/${deleted.slug}`).set('Accept-Language', 'ru-RU,ru;q=0.9').expect(410);
      expect(d.text).toContain('<html lang="ru">');
      expect(d.text).toContain('Эта визитка сейчас недоступна.');
      expect(d.text).not.toContain('Kamola');

      const u = await http().get('/c/nobody-zzzz').expect(404);
      expect(u.headers['content-type']).toMatch(/^text\/html/);
      expect(u.headers.vary).toMatch(/Accept-Language/);
      expect(u.text).toContain('<html lang="uz">');
      expect(u.text).toContain('Bu vizitka topilmadi.');
      await http().get('/c/Not%20A%20Slug').expect(404);
    });
  });

  // ───────────────────────────── vCard ─────────────────────────────

  describe('GET /c/{slug}.vcf', () => {
    it('serves a vCard 3.0 of the public fields and counts one save per visitor', async () => {
      const o = await owner({ profile: { company: 'Tanishly, Inc.', jobTitle: 'PM; Growth' } });
      const ip = nextIp();
      const res = await http().get(`/c/${o.slug}.vcf`).set('User-Agent', IPHONE).set('X-Forwarded-For', ip).expect(200);
      expect(res.headers['content-type']).toBe('text/vcard; charset=utf-8');
      expect(res.headers['content-disposition']).toBe('attachment; filename="kamola-yusupova.vcf"');
      const text = res.text;
      expect(text.startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n')).toBe(true);
      expect(text).toContain('N:Yusupova;Kamola;;;\r\n');
      expect(text).toContain('FN:Kamola Yusupova\r\n');
      expect(text).toContain('ORG:Tanishly\\, Inc.\r\n');
      expect(text).toContain('TITLE:PM\\; Growth\r\n');
      expect(text).toContain('TEL;TYPE=CELL:+998 90 123 45 67\r\n');
      expect(text).toContain('URL:https://tanishly.app/\r\n');
      expect(text).toContain(`.URL:https://metly.test/c/${o.slug}\r\n`);
      expect(text).not.toContain('EMAIL');
      expect(text).not.toContain('kamola_secret');
      expect((await stats(o)).saves).toBe(1);

      await http().get(`/c/${o.slug}.vcf`).set('User-Agent', IPHONE).set('X-Forwarded-For', ip).expect(200);
      expect((await stats(o)).saves).toBe(1);
      await webEvent(o, { type: 'save', platform: 'ios' }, ip);
      expect((await stats(o)).saves).toBe(1);
      await http().get(`/c/${o.slug}.vcf`).set('User-Agent', IPHONE).set('X-Forwarded-For', nextIp()).expect(200);
      expect((await stats(o)).saves).toBe(2);
      await http().get(`/c/${o.slug}.vcf`).set('User-Agent', BOT).set('X-Forwarded-For', nextIp()).expect(200);
      expect((await stats(o)).saves).toBe(2);
    });

    it('404 for paused, deleted and unknown cards', async () => {
      const o = await owner();
      await http().patch('/v1/me/settings').set(o.session.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
      await http().get(`/c/${o.slug}.vcf`).expect(404);
      const d = await owner();
      await http().delete(`/v1/cards/${d.cardId}`).set(d.session.auth).expect(204);
      await http().get(`/c/${d.slug}.vcf`).expect(404);
      await http().get('/c/nobody-zzzz.vcf').expect(404);
    });
  });

  // ───────────────────────────── Analytics ─────────────────────────────

  describe('POST /api/public/cards/{slug}/events', () => {
    it('dedupes views per visitor, counts QR scans, ignores bots and syncs the stats', async () => {
      const o = await owner();
      const cursor = (await pull(o.session)).body.cursor;
      const a = nextIp();
      await webEvent(o, { type: 'view', platform: 'ios', source: 'link' }, a);
      expect(await stats(o)).toMatchObject({ views: 1, scans: 0 });
      // The first change publishes the stats right away.
      const delta = await pull(o.session, cursor);
      expect(delta.body.changes.cards).toHaveLength(1);
      expect(delta.body.changes.cards[0].stats).toEqual({ views: 1, saves: 0, shareBacks: 0, scans: 0 });

      await webEvent(o, { type: 'view', platform: 'ios', source: 'link' }, a);
      await webEvent(o, { type: 'view', platform: 'ios', source: 'qr' }, a);
      expect(await stats(o)).toMatchObject({ views: 1, scans: 1 });
      await webEvent(o, { type: 'view', platform: 'android', source: 'qr' }, nextIp(), ANDROID);
      expect(await stats(o)).toMatchObject({ views: 2, scans: 2 });
      await webEvent(o, { type: 'view', platform: 'ios' }, a, ANDROID);
      expect(await stats(o)).toMatchObject({ views: 3, scans: 2 });
      await webEvent(o, { type: 'view', platform: 'ios', source: 'qr' }, nextIp(), BOT);
      await webEvent(o, { type: 'copy_phone', platform: 'ios' }, nextIp());
      expect(await stats(o)).toMatchObject({ views: 3, scans: 2, saves: 0 });
      // Raw IPs are never stored.
      const visits = await prisma.cardVisit.findMany({ where: { cardId: o.cardId } });
      expect(visits.length).toBeGreaterThan(0);
      expect(JSON.stringify(visits, (_k, v) => (typeof v === 'bigint' ? v.toString() : v))).not.toContain('203.0.113');
    });

    it('validates the body and accepts events for unavailable cards silently', async () => {
      const o = await owner();
      const bad = await http().post(`/api/public/cards/${o.slug}/events`).send({ type: 'hack', platform: 'ios' }).expect(422);
      expect(bad.body.code).toBe('validation_failed');
      await http().post('/api/public/cards/nobody-zzzz/events').send({ type: 'view', platform: 'ios' }).expect(202);
    });
  });

  // ───────────────────────────── Share-back ─────────────────────────────

  describe('share-back', () => {
    it('creates a connection the owner pulls, bumps stats, notifies (realtime + push) with the active event', async () => {
      const ev = event({ name: 'ICT Week', place: 'Expo Center' });
      const o = await owner({ changes: { events: [ev] } });
      const publish = vi.spyOn(app.get(RealtimeService), 'publish');
      const notify = vi.spyOn(app.get(PushService), 'notify');
      const cursor = (await pull(o.session)).body.cursor;

      const res = await shareBack(o, { name: '  Sardor   Rashidov ', phone: '90 765 43 21', metAt: 'Coffee line' }).expect(201);
      expectSchema('ShareBackResponse', res.body);

      const delta = await pull(o.session, cursor);
      const created = delta.body.changes.connections;
      expect(created).toHaveLength(1);
      expectSchema('Connection', created[0]);
      expect(created[0]).toMatchObject({
        fullName: 'Sardor Rashidov',
        // The owner has no device yet: the placeholder text is Uzbek.
        jobTitle: 'Kontakt',
        company: 'Veb-sahifangiz orqali yuborilgan',
        phone: '+998907654321',
        telegram: '',
        source: 'webShareBack',
        eventId: ev.id,
        mySharedCardId: o.cardId,
        context: { eventId: ev.id, eventName: 'ICT Week', place: 'Expo Center', city: 'Tashkent' },
      });
      expect(delta.body.changes.cards[0].stats.shareBacks).toBe(1);

      const call = publish.mock.calls.find(([, type]) => type === 'shareback.received');
      expect(call?.[0]).toBe(o.session.userId);
      expectSchema('ShareBackNotice', call?.[2]);
      expect(call?.[2]).toMatchObject({
        shareBackId: res.body.shareBackId,
        cardId: o.cardId,
        mergeResult: 'created',
        eventName: 'ICT Week',
        connection: { id: created[0].id },
      });
      expect(notify).toHaveBeenCalledWith(o.session.userId, {
        type: 'shareback_received',
        text: { id: 'shareBackReceived', params: { name: 'Sardor', context: 'ICT Week' } },
        data: { connectionId: created[0].id },
      });
    });

    it('uses the "Met at" text without an active event and normalises Telegram', async () => {
      const o = await owner();
      const notify = vi.spyOn(app.get(PushService), 'notify');
      await shareBack(o, { name: 'Lola', telegram: 't.me/Lola_Design', metAt: 'Tech meetup' }).expect(201);
      const connections = (await pull(o.session)).body.changes.connections;
      expect(connections[0]).toMatchObject({ telegram: '@Lola_Design', phone: '', context: { eventName: 'Tech meetup' } });
      expect(connections[0].eventId).toBeUndefined();
      expect(notify.mock.calls[0]?.[1]).toMatchObject({ text: { id: 'shareBackReceived', params: { name: 'Lola', context: null } } });
    });

    it('dedupes by phone digits and fills only the missing Telegram; removal clears just that', async () => {
      const existing = connection({ phone: '+998 90 765-43-21', telegram: '' });
      const o = await owner({ changes: { connections: [existing] } });
      const publish = vi.spyOn(app.get(RealtimeService), 'publish');
      const res = await shareBack(o, { name: 'Sardor', phone: '+998907654321', telegram: '@sardor_new' }).expect(201);

      const all = (await pull(o.session)).body.changes.connections;
      expect(all).toHaveLength(1);
      expect(all[0]).toMatchObject({ id: existing.id, phone: '+998 90 765-43-21', telegram: '@sardor_new', fullName: 'Sardor Rashidov' });
      const notice = publish.mock.calls.find(([, type]) => type === 'shareback.received')?.[2] as Record<string, unknown>;
      expect(notice.mergeResult).toBe('dedupedByPhoneOrTelegram');
      expect(notice.mergeCandidateId).toBeUndefined();

      await http().delete(`/api/public/sharebacks/${res.body.shareBackId}`).set('X-Removal-Token', res.body.removalToken).expect(204);
      const after = (await pull(o.session)).body.changes.connections;
      expect(after).toHaveLength(1);
      expect(after[0]).toMatchObject({ id: existing.id, phone: '+998 90 765-43-21', telegram: '' });
    });

    it('dedupes by Telegram case-insensitively', async () => {
      const existing = connection({ phone: '', telegram: '@Sardor' });
      const o = await owner({ changes: { connections: [existing] } });
      await shareBack(o, { name: 'Sardor R', telegram: 'sardor', phone: '+998907654321' }).expect(201);
      const all = (await pull(o.session)).body.changes.connections;
      expect(all).toHaveLength(1);
      expect(all[0]).toMatchObject({ telegram: '@Sardor', phone: '+998907654321' });
    });

    it('suggests (but never merges) a pending just-met connection with the same first name', async () => {
      const pending = connection({ fullName: 'sardor', phone: '', telegram: '', source: 'justMet', isPendingMerge: true, jobTitle: 'Met via your QR' });
      const o = await owner({ changes: { connections: [pending] } });
      const publish = vi.spyOn(app.get(RealtimeService), 'publish');
      await shareBack(o, { name: 'Sardor Rashidov', telegram: '@sardor_r' }).expect(201);
      const notice = publish.mock.calls.find(([, type]) => type === 'shareback.received')?.[2] as Record<string, unknown>;
      expectSchema('ShareBackNotice', notice);
      expect(notice).toMatchObject({ mergeResult: 'created', mergeCandidateId: pending.id });
      const all = (await pull(o.session)).body.changes.connections as { id: string; isPendingMerge: boolean; telegram: string }[];
      expect(all).toHaveLength(2);
      expect(all.find((c) => c.id === pending.id)).toMatchObject({ isPendingMerge: true, telegram: '' });
    });

    it('honeypot and paused cards: 201 but nothing stored', async () => {
      const o = await owner();
      const trap = await shareBack(o, { name: 'Bot', phone: '+998907654321', website: 'http://spam.example' }).expect(201);
      expectSchema('ShareBackResponse', trap.body);
      expect(await prisma.shareBack.count({ where: { cardId: o.cardId } })).toBe(0);

      await http().patch('/v1/me/settings').set(o.session.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
      const paused = await shareBack(o, { name: 'Sardor', phone: '+998907654321' }).expect(201);
      expectSchema('ShareBackResponse', paused.body);
      expect(await prisma.shareBack.count({ where: { cardId: o.cardId } })).toBe(0);
      expect(await prisma.connection.count({ where: { userId: o.session.userId } })).toBe(0);
      expect((await stats(o)).shareBacks).toBe(0);
      // Removing a discarded share-back is a harmless no-op.
      await http().delete(`/api/public/sharebacks/${paused.body.shareBackId}`).set('X-Removal-Token', paused.body.removalToken).expect(204);
    });

    it('validates name and phone-or-Telegram', async () => {
      const o = await owner();
      const none = await shareBack(o, { name: 'Sardor' }).expect(422);
      expect(none.body.details.phone).toBeDefined();
      expect((await shareBack(o, { name: '', phone: '+998907654321' }).expect(422)).body.details.name).toBeDefined();
      expect((await shareBack(o, { name: 'S', phone: '12' }).expect(422)).body.details.phone).toBeDefined();
      expect((await shareBack(o, { name: 'S', telegram: '@abc' }).expect(422)).body.details.telegram).toBeDefined();
      await shareBack(o, { name: 'x'.repeat(81), phone: '+998907654321' }).expect(422);
      await http().post('/api/public/cards/nobody-zzzz/shareback').send({ name: 'S', phone: '+998907654321', platform: 'ios' }).expect(404);
    });

    it('caps share-backs per IP per card and per card per day', async () => {
      const o = await owner();
      const ip = nextIp();
      for (let i = 0; i < 5; i++) await shareBack(o, { name: `P${i}`, phone: `+99890765432${i}` }, ip).expect(201);
      const limited = await shareBack(o, { name: 'P6', phone: '+998907654329' }, ip).expect(429);
      expect(limited.headers['retry-after']).toBeDefined();

      const store = app.get(RateLimitStore);
      const other = await owner();
      for (let i = 0; i < 50; i++) store.check(`shareBackPerCard:${other.cardId}`, { limit: 50, windowSeconds: 86_400, by: 'ip' });
      await shareBack(other, { name: 'Late', phone: '+998907654321' }).expect(429);
    });

    it('removal: wrong token 403, right token tombstones the created connection and its follow-ups, idempotent', async () => {
      const o = await owner();
      const res = await shareBack(o, { name: 'Nodira', phone: '+998935554433' }).expect(201);
      const created = (await pull(o.session)).body.changes.connections[0];
      const reminder = followUp({ connectionId: created.id });
      await push(o.session, { followUps: [reminder] });
      const cursor = (await pull(o.session)).body.cursor;

      const wrong = await http().delete(`/api/public/sharebacks/${res.body.shareBackId}`).set('X-Removal-Token', 'nope').expect(403);
      expect(wrong.body.code).toBe('forbidden');
      await http().delete(`/api/public/sharebacks/${res.body.shareBackId}`).expect(403);

      await http().delete(`/api/public/sharebacks/${res.body.shareBackId}`).set('X-Removal-Token', res.body.removalToken).expect(204);
      const delta = await pull(o.session, cursor);
      expect(delta.body.changes.tombstones).toEqual(
        expect.arrayContaining([
          { type: 'connection', id: created.id, deletedAt: expect.any(String) },
          { type: 'followUp', id: reminder.id, deletedAt: expect.any(String) },
        ]),
      );
      await http().delete(`/api/public/sharebacks/${res.body.shareBackId}`).set('X-Removal-Token', res.body.removalToken).expect(204);
      await http().delete(`/api/public/sharebacks/${randomUUID()}`).set('X-Removal-Token', 'x').expect(204);
    });

    it('drops share-backs from a person the owner blocked', async () => {
      const blocked = connection({ phone: '+998907654321', isBlocked: true });
      const o = await owner({ changes: { connections: [blocked] } });
      await shareBack(o, { name: 'Sardor', phone: '907654321' }).expect(201);
      expect(await prisma.shareBack.count({ where: { cardId: o.cardId } })).toBe(0);
      expect((await stats(o)).shareBacks).toBe(0);
    });
  });

  // ───────────────────────────── Deferred links ─────────────────────────────

  describe('deferred links', () => {
    const getApp = (o: Owner, ip: string, query: Record<string, string> = { tz: 'Asia/Tashkent', lang: 'en-US' }, ua = IPHONE) =>
      http().get(`/c/${o.slug}/get-app`).query(query).set('User-Agent', ua).set('X-Forwarded-For', ip).expect(302);
    const claim = (body: Record<string, unknown>, ip: string) =>
      http().post('/v1/deferred-links/claim').set('X-Forwarded-For', ip).send({ fingerprint: FINGERPRINT, ...body }).expect(200);

    it('records a click (network prefix only) and redirects', async () => {
      const ev = event({ name: 'ICT Week' });
      const o = await owner({ changes: { events: [ev] } });
      const res = await getApp(o, '198.51.100.23');
      expect(res.headers.location).toBe('https://metly.test');
      const click = await prisma.deferredClick.findFirstOrThrow({ where: { cardId: o.cardId } });
      expect(click).toMatchObject({ ipPrefix: '198.51.100.0/24', timeZone: 'Asia/Tashkent', locale: 'en-US', eventName: 'ICT Week', ownerId: o.session.userId });
      expect(JSON.stringify(click)).not.toContain('198.51.100.23');
      await getApp(o, '198.51.100.24', {}, BOT);
      expect(await prisma.deferredClick.count({ where: { cardId: o.cardId } })).toBe(1);
    });

    it('claims by explicit token once; the same install gets the same invite again', async () => {
      const o = await owner();
      await getApp(o, '198.51.101.9');
      const click = await prisma.deferredClick.findFirstOrThrow({ where: { cardId: o.cardId } });
      const installId = randomUUID();
      const res = await claim({ installId, token: click.token }, '192.0.2.1');
      expectSchema('DeferredLinkClaimResponse', res.body);
      expect(res.body.invite).toMatchObject({
        inviteId: click.id,
        cardSlug: o.slug,
        owner: { userId: o.session.userId, fullName: 'Kamola Yusupova', jobTitle: 'Product Manager', company: 'Tanishly' },
        card: { cardName: 'Work', fullName: 'Kamola Yusupova' },
      });
      expect(res.body.invite.card.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'website']);
      expect((await claim({ installId, token: click.token }, '192.0.2.1')).body.invite.inviteId).toBe(click.id);
      expect((await claim({ installId: randomUUID(), token: click.token }, '198.51.101.9')).body.invite).toBeNull();
    });

    it('matches by fingerprint, single use; null when ambiguous or mismatched', async () => {
      const o = await owner();
      await getApp(o, '198.51.102.40');
      const ok = await claim({ installId: randomUUID() }, '198.51.102.77');
      expectSchema('DeferredLinkClaimResponse', ok.body);
      expect(ok.body.invite.cardSlug).toBe(o.slug);
      expect((await claim({ installId: randomUUID() }, '198.51.102.77')).body.invite).toBeNull();

      // Wrong time zone / other network → nothing.
      await getApp(o, '198.51.103.5');
      expect((await claim({ installId: randomUUID(), fingerprint: { ...FINGERPRINT, timeZone: 'Europe/Berlin' } }, '198.51.103.6')).body.invite).toBeNull();
      expect((await claim({ installId: randomUUID() }, '198.51.104.6')).body.invite).toBeNull();

      // Two different cards, identical fingerprints on one network → ambiguous.
      const a = await owner();
      const b = await owner();
      await getApp(a, '198.51.105.1');
      await getApp(b, '198.51.105.2');
      expect((await claim({ installId: randomUUID() }, '198.51.105.3')).body.invite).toBeNull();
    });

    it('returns null once the card is paused', async () => {
      const o = await owner();
      await getApp(o, '198.51.106.1');
      await http().patch('/v1/me/settings').set(o.session.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
      expect((await claim({ installId: randomUUID() }, '198.51.106.2')).body.invite).toBeNull();
    });

    it('validates the claim body', async () => {
      await http().post('/v1/deferred-links/claim').send({ installId: 'x' }).expect(422);
    });
  });

  // ───────────────────────────── AASA ─────────────────────────────

  it('serves an empty apple-app-site-association without a team id', async () => {
    const res = await http().get('/.well-known/apple-app-site-association').expect(200);
    expect(res.headers['content-type']).toMatch(/^application\/json/);
    expect(res.body).toEqual({ applinks: { apps: [], details: [] }, webcredentials: { apps: [] } });
  });
});

describe('public web with App Store and team ids', () => {
  let app: NestExpressApplication;
  const saved = { team: process.env.APPLE_TEAM_ID, store: process.env.APP_STORE_ID };

  beforeAll(async () => {
    process.env.APPLE_TEAM_ID = 'TEAM123456';
    process.env.APP_STORE_ID = '6700000001';
    app = await createApp();
  });
  afterAll(async () => {
    await app.close();
    for (const [key, value] of [
      ['APPLE_TEAM_ID', saved.team],
      ['APP_STORE_ID', saved.store],
    ] as const) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it('AASA lists the app ids for /c/*', async () => {
    for (const path of ['/.well-known/apple-app-site-association', '/apple-app-site-association']) {
      const res = await request(app.getHttpServer()).get(path).expect(200);
      expect(res.headers['content-type']).toMatch(/^application\/json/);
      expect(res.body.applinks.details[0].appIDs).toEqual(['TEAM123456.app.tanishly.ios']);
      expect(res.body.applinks.details[0].components).toContainEqual({ '/': '/c/*', comment: 'Card pages' });
      expect(res.body.webcredentials.apps).toEqual(['TEAM123456.app.tanishly.ios']);
    }
  });

  it('adds the Smart App Banner and a "Get Tanishly" button that redirects to the App Store', async () => {
    const session = await signIn(app);
    const c = card({ design: allFields });
    const pushed = await request(app.getHttpServer())
      .post('/v1/sync/push')
      .set(session.auth)
      .send({ deviceId: 'd', changes: { profile: profile(), cards: [c] } })
      .expect(200);
    const slug = pushed.body.records.cards[0].slug;
    const page = await request(app.getHttpServer()).get(`/c/${slug}`).set('User-Agent', IPHONE).expect(200);
    expect(page.text).toContain(`<meta name="apple-itunes-app" content="app-id=6700000001, app-argument=https://metly.test/c/${slug}">`);
    expect(page.text).toContain(`href="/c/${slug}/get-app"`);
    const redirect = await request(app.getHttpServer()).get(`/c/${slug}/get-app`).set('User-Agent', IPHONE).expect(302);
    expect(redirect.headers.location).toBe('https://apps.apple.com/app/id6700000001');
  });
});
