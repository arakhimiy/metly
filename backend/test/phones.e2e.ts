import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { expectSchema } from './contract';
import { card, connection, createApp, design, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

// Labelled phones (docs/api/README.md § Labelled phones): sync, old clients, public surfaces, connect.

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';

const workPublic = { id: randomUUID(), label: 'work', value: '+998 71 200 00 00', privacy: 'public' };
const homeConnections = { id: randomUUID(), label: 'home', value: '+998 71 300 00 00', privacy: 'connections' };
const otherPrivate = { id: randomUUID(), label: 'other', value: '+998 71 400 00 00', privacy: 'private' };
const phones = [workPublic, homeConnections, otherPrivate];

describe('labelled phones', () => {
  let app: NestExpressApplication;

  beforeAll(async () => {
    app = await createApp();
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  const http = () => request(app.getHttpServer());
  const push = (s: Session, changes: Record<string, unknown>) =>
    http().post('/v1/sync/push').set(s.auth).send({ deviceId: 'device-1', changes }).expect(200);
  const pull = (s: Session) => http().get('/v1/sync').set(s.auth).expect(200);
  /** The payload an app build from before labelled phones sends: no `phoneLabel`, no `additionalPhones`. */
  const withoutPhoneKeys = (record: Record<string, unknown>) => {
    const { phoneLabel: _label, additionalPhones: _phones, ...rest } = record;
    return rest;
  };

  /** A signed-in owner whose profile has a public mobile plus Work (Public), Home (Connections), Other (Private). */
  async function owner(name = 'Kamola Yusupova', overrides: Record<string, unknown> = {}) {
    const s = await signIn(app, randomUUID(), name);
    const p = profile({ fullName: name, phoneLabel: 'mobile', additionalPhones: phones, ...overrides });
    const c = card({ design: { ...design, visibleFields: ['phone', 'email', 'telegram'] } });
    const res = await push(s, { profile: p, cards: [c] });
    return { s, userId: s.userId, profile: p, cardId: c.id, slug: res.body.records.cards[0].slug as string, name };
  }

  // ───────────────────────────── Sync ─────────────────────────────

  it('round-trips phoneLabel + additionalPhones and always returns them (defaults for new records)', async () => {
    const o = await owner();
    const full = await pull(o.s);
    expectSchema('SyncPullResponse', full.body);
    expect(full.body.changes.profile).toMatchObject({ phoneLabel: 'mobile', additionalPhones: phones });

    const s = await signIn(app);
    const plain = await push(s, { profile: profile(), connections: [connection()] });
    expectSchema('SyncPushResponse', plain.body);
    expect(plain.body.records.profile).toMatchObject({ phoneLabel: 'mobile', additionalPhones: [] });
    expect(plain.body.records.connections[0]).toMatchObject({ phoneLabel: 'mobile', additionalPhones: [] });
  });

  it('an older client that omits the keys keeps the stored phones (profile and connection)', async () => {
    const o = await owner();
    const res = await push(o.s, { profile: { ...withoutPhoneKeys(o.profile), jobTitle: 'Head of Product', updatedAt: now(1000) } });
    expect(res.body.results[0].status).toBe('applied');
    expect(res.body.records.profile).toMatchObject({ jobTitle: 'Head of Product', phoneLabel: 'mobile', additionalPhones: phones });

    const c = connection({ phoneLabel: 'work', additionalPhones: [{ id: randomUUID(), label: 'home', value: '+998 71 555 55 55' }] });
    const created = await push(o.s, { connections: [c] });
    expect(created.body.records.connections[0]).toMatchObject({ phoneLabel: 'work', additionalPhones: [expect.objectContaining({ privacy: 'connections' })] });
    const edited = await push(o.s, { connections: [{ ...withoutPhoneKeys(c), note: 'Edited on an old build', updatedAt: now(2000) }] });
    expect(edited.body.records.connections[0]).toMatchObject({
      note: 'Edited on an old build',
      phoneLabel: 'work',
      additionalPhones: [expect.objectContaining({ value: '+998 71 555 55 55' })],
    });
  });

  it('rejects more than 5 extra phones, over-long numbers and unknown labels (validation_failed, record by record)', async () => {
    const o = await owner();
    const six = Array.from({ length: 6 }, (_, i) => ({ ...workPublic, id: randomUUID(), value: `+998 71 000 00 0${i}` }));
    const ok = connection();
    const res = await push(o.s, {
      profile: { ...o.profile, additionalPhones: six, updatedAt: now(1000) },
      connections: [ok, connection({ additionalPhones: [{ ...workPublic, value: '1'.repeat(41) }] }), connection({ phoneLabel: 'fax' })],
    });
    expect(res.body.results.map((r: { status: string }) => r.status)).toEqual(['rejected', 'applied', 'rejected', 'rejected']);
    expect(res.body.results[0].error.code).toBe('validation_failed');
    const rest = await http().put('/v1/me/profile').set(o.s.auth).send({ ...o.profile, additionalPhones: six, updatedAt: now(2000) }).expect(422);
    expect(rest.body.code).toBe('validation_failed');
    expect((await pull(o.s)).body.changes.profile.additionalPhones).toEqual(phones);
  });

  // ───────────────────────────── Public surfaces ─────────────────────────────

  it('public JSON, page and vCard show Public extra phones only, with labels', async () => {
    const o = await owner();
    const json = await http().get(`/api/public/cards/${o.slug}`).expect(200);
    expectSchema('PublicCard', json.body);
    expect(json.body.phoneLabel).toBe('mobile');
    expect(json.body.additionalPhones).toEqual([workPublic]);
    expect(JSON.stringify(json.body)).not.toContain(homeConnections.value);
    expect(JSON.stringify(json.body)).not.toContain(otherPrivate.value);

    const en = await http().get(`/c/${o.slug}?lang=en`).set('User-Agent', IPHONE).expect(200);
    expect(en.text).toContain('<span class="label">mobile</span><span class="value">+998901234567</span>');
    expect(en.text).toContain('href="tel:+998712000000"');
    expect(en.text).toContain('<span class="label">work phone</span><span class="value">+998 71 200 00 00</span>');
    expect(en.text).not.toContain(homeConnections.value);
    expect(en.text.indexOf('+998901234567')).toBeLessThan(en.text.indexOf('+998 71 200 00 00'));
    const ru = await http().get(`/c/${o.slug}?lang=ru`).set('User-Agent', IPHONE).expect(200);
    expect(ru.text).toContain('<span class="label">мобильный</span>');
    expect(ru.text).toContain('<span class="label">рабочий телефон</span>');
    const uz = await http().get(`/c/${o.slug}`).set('User-Agent', IPHONE).expect(200);
    expect(uz.text).toContain('<span class="label">mobil</span>');
    expect(uz.text).toContain('<span class="label">ish telefoni</span>');

    const vcf = await http().get(`/c/${o.slug}.vcf`).set('User-Agent', IPHONE).expect(200);
    expect(vcf.text).toContain('TEL;TYPE=CELL:+998901234567\r\nTEL;TYPE=WORK:+998 71 200 00 00\r\n');
    expect(vcf.text).not.toContain(homeConnections.value);
  });

  it('a single mobile phone keeps the plain "phone" label; extras need the card to show phones', async () => {
    const solo = await owner('Solo Person', { additionalPhones: [] });
    const page = await http().get(`/c/${solo.slug}?lang=en`).set('User-Agent', IPHONE).expect(200);
    expect(page.text).toContain('<span class="label">phone</span>');

    const s = await signIn(app);
    const c = card({ design: { ...design, visibleFields: ['email'] } });
    const res = await push(s, { profile: profile({ additionalPhones: phones }), cards: [c] });
    const hidden = await http().get(`/api/public/cards/${res.body.records.cards[0].slug}`).expect(200);
    expect(hidden.body.additionalPhones).toEqual([]);
  });

  // ───────────────────────────── App: public profile + connect ─────────────────────────────

  it('the app route adds Connections-level extras after a mutual connect, and accepting copies them', async () => {
    const a = await owner('Aziza Karimova', { phoneLabel: 'work' });
    const b = await owner('Bobur Aliev', { additionalPhones: [] });
    const view = () => http().get(`/v1/public-profiles/${a.slug}`).set(b.s.auth).expect(200);

    const stranger = await view();
    expectSchema('PublicCard', stranger.body);
    expect(stranger.body.phoneLabel).toBe('work');
    expect(stranger.body.additionalPhones).toEqual([workPublic]);

    const sent = await http()
      .post('/v1/connect/requests')
      .set(b.s.auth)
      .set('Idempotency-Key', randomUUID())
      .send({ cardId: b.cardId, method: 'scan', toSlug: a.slug })
      .expect(201);
    const accepted = await http().post(`/v1/connect/requests/${sent.body.id}/accept`).set(a.s.auth).send({ cardId: a.cardId }).expect(200);
    expectSchema('ConnectAcceptResponse', accepted.body);
    // Aziza's connection to Bobur: his single mobile number, nothing invented.
    expect(accepted.body.connection).toMatchObject({ phone: '+998901234567', phoneLabel: 'mobile', additionalPhones: [] });

    const mutual = await view();
    expect(mutual.body.additionalPhones).toEqual([workPublic, homeConnections]);

    // Bobur's connection to Aziza: her Work-labelled primary + Work and Home extras (never the Private one).
    const bobursSide = (await pull(b.s)).body.changes.connections.find((c: { remoteUserId: string }) => c.remoteUserId === a.userId);
    expectSchema('Connection', bobursSide);
    expect(bobursSide).toMatchObject({ phone: '+998901234567', phoneLabel: 'work' });
    expect(bobursSide.additionalPhones.map((p: { label: string; value: string; privacy: string }) => [p.label, p.value, p.privacy])).toEqual([
      ['work', workPublic.value, 'connections'],
      ['home', homeConnections.value, 'connections'],
    ]);
    expect(JSON.stringify(bobursSide)).not.toContain(otherPrivate.value);
    // The frozen card snapshot stays as it was (no phones beyond `fields`).
    expect(bobursSide.theirCard.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);
  });
});
