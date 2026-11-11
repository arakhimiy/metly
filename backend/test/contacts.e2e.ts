import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PrismaService } from '../src/prisma/prisma.service';
import { expectSchema } from './contract';
import { card, connection, createApp, design, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

// Contact list (docs/api/CONTACTS.md): sync round-trip, legacy derivation both ways, validation,
// card selection on public surfaces, connect, share-back and rows from before the list.

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const PRIMARY = {
  phone: '00000000-0000-0000-0000-00000000f001',
  email: '00000000-0000-0000-0000-00000000f002',
  telegram: '00000000-0000-0000-0000-00000000f003',
  website: '00000000-0000-0000-0000-00000000f004',
  linkedin: '00000000-0000-0000-0000-00000000f005',
};

type Entry = { id: string; kind: string; label: string | null; value: string; privacy: string };
const entry = (kind: string, value: string, privacy: string, label: string | null = kind === 'phone' ? 'mobile' : null): Entry => ({
  id: randomUUID(),
  kind,
  label,
  value,
  privacy,
});

/** A fresh list per owner: ids are unique per list, not globally, but fresh ones keep assertions honest. */
function contactList() {
  const mobile = entry('phone', '+998 90 123 45 67', 'public');
  const whatsapp = entry('whatsapp', '+998 90 123 45 67', 'public');
  const work = entry('phone', '+998 71 200 00 00', 'connections', 'work');
  const email = entry('email', 'kamola@metly.test', 'public');
  const instagram = entry('instagram', '@kamola.y', 'public');
  const secret = entry('email', 'secret@metly.test', 'private');
  const telegram = entry('telegram', '@kamola_tg', 'connections');
  return { mobile, whatsapp, work, email, instagram, secret, telegram, all: [mobile, whatsapp, work, email, instagram, secret, telegram] };
}

describe('contact list', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  const http = () => request(app.getHttpServer());
  const push = (s: Session, changes: Record<string, unknown>) =>
    http().post('/v1/sync/push').set(s.auth).send({ deviceId: 'device-1', changes }).expect(200);
  const pull = (s: Session) => http().get('/v1/sync').set(s.auth).expect(200);
  /** What an app from before the contact list sends. */
  const withoutContacts = (record: Record<string, unknown>) => {
    const { contacts: _contacts, ...rest } = record;
    return rest;
  };

  async function owner(name = 'Kamola Yusupova', cardDesign: Record<string, unknown> = design) {
    const s = await signIn(app, randomUUID(), name);
    const list = contactList();
    const p = profile({ fullName: name, contacts: list.all });
    const c = card({ design: cardDesign });
    const res = await push(s, { profile: p, cards: [c] });
    return { s, list, profile: p, card: c, res, slug: res.body.records.cards[0].slug as string };
  }

  // ───────────────────────────── Sync ─────────────────────────────

  it('round-trips the list and derives the legacy fields in every response', async () => {
    const o = await owner();
    const { mobile, work, email, telegram } = o.list;
    expectSchema('SyncPushResponse', o.res.body);
    const pushed = o.res.body.records.profile;
    expect(pushed.contacts).toEqual(o.list.all);
    expect(pushed.contactFields).toEqual([
      { kind: 'phone', value: mobile.value, privacy: 'public' },
      { kind: 'email', value: email.value, privacy: 'public' },
      { kind: 'telegram', value: telegram.value, privacy: 'connections' },
      { kind: 'website', value: '', privacy: 'public' },
      { kind: 'linkedin', value: '', privacy: 'connections' },
    ]);
    expect(pushed.phoneLabel).toBe('mobile');
    expect(pushed.additionalPhones).toEqual([{ id: work.id, label: 'work', value: work.value, privacy: 'connections' }]);

    const full = await pull(o.s);
    expectSchema('SyncPullResponse', full.body);
    expect(full.body.changes.profile).toMatchObject({ contacts: o.list.all, phoneLabel: 'mobile' });
    const rest = await http().get('/v1/me/profile').set(o.s.auth).expect(200);
    expectSchema('Profile', rest.body);
    expect(rest.body.contacts).toEqual(o.list.all);

    // A connection: the columns come from the list, privacy may be omitted.
    const c = connection({
      phone: '',
      telegram: '',
      contacts: [
        { id: randomUUID(), kind: 'instagram', value: '@sardor' },
        { id: randomUUID(), kind: 'phone', label: 'work', value: '+998 71 555 55 55' },
        { id: randomUUID(), kind: 'whatsapp', label: 'home', value: '+998 90 765 43 21' },
        { id: randomUUID(), kind: 'phone', label: 'home', value: '+998 71 666 66 66' },
        { id: randomUUID(), kind: 'website', value: 'acme.uz' },
      ],
    });
    const created = (await push(o.s, { connections: [c] })).body.records.connections[0];
    expectSchema('Connection', created);
    expect(created).toMatchObject({ phone: '+998 71 555 55 55', phoneLabel: 'work', email: '', telegram: '', website: 'acme.uz', linkedin: '' });
    expect(created.additionalPhones).toEqual([expect.objectContaining({ label: 'home', value: '+998 71 666 66 66', privacy: 'connections' })]);
    expect(created.contacts.map((e: Entry) => [e.kind, e.label, e.privacy])).toEqual([
      ['instagram', null, 'connections'],
      ['phone', 'work', 'connections'],
      ['whatsapp', null, 'connections'],
      ['phone', 'home', 'connections'],
      ['website', null, 'connections'],
    ]);
  });

  it('a long website entry (≤ 500) is accepted and carried by the derived contactFields', async () => {
    const o = await owner();
    const site = entry('website', `https://kamola.uz/${'a'.repeat(450)}`, 'public');
    const p = { ...o.profile, contacts: [...o.list.all.slice(0, 6), site], updatedAt: now(1000) };
    const res = await push(o.s, { profile: p });
    expect(res.body.results[0].status).toBe('applied');
    expectSchema('Profile', res.body.records.profile);
    expect(res.body.records.profile.contactFields.find((f: { kind: string }) => f.kind === 'website').value).toBe(site.value);
    // The new app's next push echoes the derived contactFields back: still valid.
    const again = await push(o.s, { profile: { ...res.body.records.profile, updatedAt: now(2000) } });
    expect(again.body.results[0].status).toBe('applied');
  });

  it('PATCH /v1/me/settings keeps the list', async () => {
    const o = await owner();
    await http().patch('/v1/me/settings').set(o.s.auth).set('Idempotency-Key', randomUUID()).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
    expect((await http().get('/v1/me/profile').set(o.s.auth).expect(200)).body.contacts).toEqual(o.list.all);
  });

  it('an older app’s push (no contacts) rebuilds what the legacy fields express and keeps WhatsApp/Instagram/second emails', async () => {
    const o = await owner();
    const { mobile, whatsapp, work, instagram, secret } = o.list;
    const old = withoutContacts({
      ...o.profile,
      contactFields: [
        { kind: 'phone', value: '+998 90 999 99 99', privacy: 'public' },
        { kind: 'email', value: 'new@metly.test', privacy: 'connections' },
        { kind: 'telegram', value: '', privacy: 'public' },
        { kind: 'website', value: 'kamola.uz', privacy: 'public' },
        { kind: 'linkedin', value: '', privacy: 'public' },
      ],
      phoneLabel: 'home',
      additionalPhones: [{ id: work.id, label: 'work', value: work.value, privacy: 'connections' }],
      updatedAt: now(1000),
    });
    const res = await push(o.s, { profile: old });
    expect(res.body.results[0].status).toBe('applied');
    const p = res.body.records.profile;
    expectSchema('Profile', p);
    expect(p.contacts.map((e: Entry) => [e.kind, e.value, e.privacy])).toEqual([
      ['phone', '+998 90 999 99 99', 'public'],
      ['phone', work.value, 'connections'],
      ['email', 'new@metly.test', 'connections'],
      ['website', 'kamola.uz', 'public'],
      ['whatsapp', whatsapp.value, 'public'],
      ['instagram', instagram.value, 'public'],
      ['email', secret.value, 'private'],
    ]);
    // Ids stay stable: the replaced primary phone and first email keep theirs, a new website gets the fixed id.
    expect(p.contacts[0]).toMatchObject({ id: mobile.id, label: 'home' });
    expect(p.contacts[1].id).toBe(work.id);
    expect(p.contacts[2].id).toBe(o.list.email.id);
    expect(p.contacts[3].id).toBe(PRIMARY.website);
    expect(p.contacts.slice(4)).toEqual([whatsapp, instagram, secret]);
    expect(p.phoneLabel).toBe('home');

    // An app from before labelled phones too (no phoneLabel / additionalPhones): stored ones kept.
    const older = withoutContacts({ ...o.profile, updatedAt: now(2000) });
    delete (older as Record<string, unknown>).phoneLabel;
    delete (older as Record<string, unknown>).additionalPhones;
    const kept = (await push(o.s, { profile: older })).body.records.profile;
    expect(kept.phoneLabel).toBe('home');
    expect(kept.additionalPhones.map((x: Entry) => x.id)).toEqual([work.id]);
    expect(kept.contacts.map((e: Entry) => e.kind)).toContain('whatsapp');

    // The same for a connection.
    const c = connection({ contacts: [entry('phone', '+998 90 765 43 21', 'connections'), entry('instagram', '@sardor', 'connections')] });
    await push(o.s, { connections: [c] });
    const edited = (await push(o.s, { connections: [{ ...withoutContacts(c), telegram: '@sardor_r', updatedAt: now(3000) }] })).body.records.connections[0];
    expectSchema('Connection', edited);
    expect(edited.contacts.map((e: Entry) => [e.kind, e.value])).toEqual([
      ['phone', '+998907654321'],
      ['telegram', '@sardor_r'],
      ['instagram', '@sardor'],
    ]);
    expect(edited).toMatchObject({ phone: '+998907654321', telegram: '@sardor_r' });
  });

  it('rejects 11 entries, unknown kinds, over-long or empty values and duplicate ids (validation_failed, record by record)', async () => {
    const o = await owner();
    const eleven = Array.from({ length: 11 }, (_, i) => entry('email', `a${i}@metly.test`, 'public'));
    const dup = entry('instagram', '@x', 'public');
    const res = await push(o.s, {
      profile: { ...o.profile, contacts: eleven, updatedAt: now(1000) },
      connections: [
        connection(),
        connection({ contacts: [{ ...dup, kind: 'fax' }] }),
        connection({ contacts: [entry('whatsapp', '1'.repeat(41), 'connections')] }),
        connection({ contacts: [entry('email', '   ', 'connections')] }),
        connection({ contacts: [dup, { ...dup, value: '@y' }] }),
        connection({ contacts: [entry('website', `https://${'a'.repeat(500)}.uz`, 'connections')] }),
      ],
    });
    expectSchema('SyncPushResponse', res.body);
    expect(res.body.results.map((r: { status: string }) => r.status)).toEqual(['rejected', 'applied', 'rejected', 'rejected', 'rejected', 'rejected', 'rejected']);
    expect(res.body.results[0].error.code).toBe('validation_failed');

    const rest = await http().put('/v1/me/profile').set(o.s.auth).send({ ...o.profile, contacts: [entry('phone', '1'.repeat(41), 'public')], updatedAt: now(2000) }).expect(422);
    expect(rest.body.code).toBe('validation_failed');
    expect(rest.body.details).toHaveProperty(['contacts.0.value']);
    expect((await pull(o.s)).body.changes.profile.contacts).toEqual(o.list.all);
  });

  // ───────────────────────────── Cards ─────────────────────────────

  it('a card’s visibleContacts picks the entries on the public JSON, page and vCard (selection, then audience)', async () => {
    const s = await signIn(app, randomUUID(), 'Kamola Yusupova');
    const list = contactList();
    const { mobile, whatsapp, work, email, instagram, secret, telegram } = list;
    const selection = [instagram.id, secret.id, whatsapp.id, work.id, randomUUID(), instagram.id];
    const c = card({ design: { ...design, visibleFields: ['phone', 'email'], visibleContacts: selection } });
    const res = await push(s, { profile: profile({ contacts: list.all }), cards: [c] });
    const stored = res.body.records.cards[0];
    expectSchema('Card', stored);
    // Deduplicated, unknown ids kept (ignored when rendering).
    expect(stored.design.visibleContacts).toEqual([instagram.id, secret.id, whatsapp.id, work.id, selection[4]]);
    const slug = stored.slug as string;

    const json = await http().get(`/api/public/cards/${slug}`).expect(200);
    expectSchema('PublicCard', json.body);
    expect(json.body.contacts).toEqual([whatsapp, instagram]);
    expect(json.body.fields).toEqual([]);
    expect(json.body.additionalPhones).toEqual([]);
    expect(json.body.phoneLabel).toBe('mobile');
    for (const hidden of [work.value, secret.value, email.value, telegram.value]) expect(JSON.stringify(json.body)).not.toContain(hidden);

    const page = await http().get(`/c/${slug}?lang=en`).set('User-Agent', IPHONE).expect(200);
    expect(page.text).toContain('href="https://wa.me/998901234567"');
    expect(page.text).toContain('<span class="label">WhatsApp</span><span class="value">+998 90 123 45 67</span>');
    expect(page.text).toContain('href="https://instagram.com/kamola.y"');
    expect(page.text).toContain('<span class="label">instagram</span><span class="value">@kamola.y</span>');
    expect(page.text.indexOf('wa.me')).toBeLessThan(page.text.indexOf('instagram.com/kamola.y'));
    expect(page.text).not.toContain(work.value);
    expect(page.text).not.toContain(secret.value);
    const ru = await http().get(`/c/${slug}?lang=ru`).set('User-Agent', IPHONE).expect(200);
    expect(ru.text).toContain('<span class="label">WhatsApp</span>');

    const vcf = await http().get(`/c/${slug}.vcf`).set('User-Agent', IPHONE).expect(200);
    expect(vcf.text).toContain('X-SOCIALPROFILE;TYPE=whatsapp:https://wa.me/998901234567\r\n');
    expect(vcf.text).toContain('X-SOCIALPROFILE;TYPE=instagram:https://instagram.com/kamola.y\r\n');
    expect(vcf.text).not.toContain('TEL');
    expect(vcf.text).not.toContain(secret.value);

    // Every phone and both public emails once the card selects them; page in profile order.
    const all = card({ design: { ...design, visibleContacts: [mobile.id, work.id, email.id, secret.id, telegram.id] } });
    const second = (await push(s, { cards: [all] })).body.records.cards[0].slug as string;
    const both = await http().get(`/api/public/cards/${second}`).expect(200);
    expect(both.body.contacts).toEqual([mobile, email]);
    expect(both.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);
  });

  it('a legacy card (no visibleContacts) shows its visibleFields kinds — every phone and email, never WhatsApp/Instagram', async () => {
    const o = await owner('Legacy Card', { ...design, visibleFields: ['phone', 'email', 'telegram'] });
    const { mobile, email } = o.list;
    expect(o.res.body.records.cards[0].design.visibleContacts).toBeUndefined();
    const json = await http().get(`/api/public/cards/${o.slug}`).expect(200);
    expectSchema('PublicCard', json.body);
    expect(json.body.contacts).toEqual([mobile, email]);
    const page = await http().get(`/c/${o.slug}?lang=en`).set('User-Agent', IPHONE).expect(200);
    expect(page.text).not.toContain('wa.me');
    expect(page.text).not.toContain('instagram.com');

    // An older app's card write (no key) turns a selection back into a legacy card.
    const picked = { ...o.card, design: { ...design, visibleContacts: [o.list.whatsapp.id] }, updatedAt: now(1000) };
    expect((await push(o.s, { cards: [picked] })).body.records.cards[0].design.visibleContacts).toEqual([o.list.whatsapp.id]);
    const reverted = (await push(o.s, { cards: [{ ...picked, design, updatedAt: now(2000) }] })).body.records.cards[0];
    expect(reverted.design.visibleContacts).toBeUndefined();
  });

  // ───────────────────────────── Connect ─────────────────────────────

  it('after a mutual connect the app route adds Connections-level entries, and accepting copies them without duplicates', async () => {
    const a = await owner('Aziza Karimova', { ...design, visibleContacts: [] });
    const { whatsapp, work, instagram, secret, telegram, mobile } = a.list;
    const selected = { ...a.card, design: { ...design, visibleContacts: [whatsapp.id, work.id, instagram.id, secret.id, telegram.id] }, updatedAt: now(500) };
    await push(a.s, { cards: [selected] });
    const b = await owner('Bobur Aliev');
    const view = () => http().get(`/v1/public-profiles/${a.slug}`).set(b.s.auth).expect(200);
    const stranger = await view();
    expectSchema('PublicCard', stranger.body);
    expect(stranger.body.contacts).toEqual([whatsapp, instagram]);

    const sent = await http()
      .post('/v1/connect/requests')
      .set(b.s.auth)
      .set('Idempotency-Key', randomUUID())
      .send({ cardId: b.card.id, method: 'scan', toSlug: a.slug })
      .expect(201);
    const accepted = await http().post(`/v1/connect/requests/${sent.body.id}/accept`).set(a.s.auth).send({ cardId: a.card.id }).expect(200);
    expectSchema('ConnectAcceptResponse', accepted.body);
    // Aziza's connection to Bobur: his legacy card (phone, email, telegram kinds) at Connections level.
    expect(accepted.body.connection.contacts.map((e: Entry) => e.kind)).toEqual(['phone', 'phone', 'email', 'telegram']);
    expect(JSON.stringify(accepted.body.connection)).not.toContain('secret@metly.test');

    const mutual = await view();
    expect(mutual.body.contacts).toEqual([whatsapp, work, instagram, telegram]);

    const bobursSide = (await pull(b.s)).body.changes.connections.find((c: { remoteUserId?: string }) => c.remoteUserId === a.s.userId);
    expectSchema('Connection', bobursSide);
    expect(bobursSide.contacts.map((e: Entry) => [e.kind, e.value, e.privacy])).toEqual([
      ['whatsapp', whatsapp.value, 'connections'],
      ['phone', work.value, 'connections'],
      ['instagram', instagram.value, 'connections'],
      ['telegram', telegram.value, 'connections'],
    ]);
    expect(bobursSide).toMatchObject({ phone: work.value, phoneLabel: 'work', telegram: telegram.value });
    expect(JSON.stringify(bobursSide)).not.toContain(secret.value);
    expect(JSON.stringify(bobursSide.contacts)).not.toContain(mobile.value.replace(/ /g, ''));

    // A second record for the same person (e.g. a paper card) merges into it: the same WhatsApp number
    // written differently is not duplicated, the new email is appended, the pushed id is tombstoned.
    const paper = connection({
      fullName: 'Aziza',
      remoteUserId: a.s.userId,
      phone: '',
      telegram: '',
      contacts: [entry('whatsapp', '998901234567', 'connections'), entry('email', 'aziza@paper.uz', 'connections')],
      updatedAt: now(1000),
    });
    const res = await push(b.s, { connections: [paper] });
    const survivor = res.body.records.connections.find((c: { id: string }) => c.id === bobursSide.id);
    expectSchema('Connection', survivor);
    expect(survivor.contacts.map((e: Entry) => [e.kind, e.value])).toEqual([
      ['whatsapp', '998901234567'],
      ['email', 'aziza@paper.uz'],
      ['phone', work.value],
      ['instagram', instagram.value],
      ['telegram', telegram.value],
    ]);
    expect(survivor).toMatchObject({ email: 'aziza@paper.uz', phone: work.value });
    expect(res.body.records.tombstones).toContainEqual(expect.objectContaining({ type: 'connection', id: paper.id }));
  });

  // ───────────────────────────── Share-back ─────────────────────────────

  it('a share-back becomes connection entries, dedupes against WhatsApp entries, and removal takes back only what it added', async () => {
    const o = await owner('Share Owner');
    const created = await http()
      .post(`/api/public/cards/${o.slug}/shareback`)
      .set('X-Forwarded-For', '203.0.113.71')
      .send({ platform: 'ios', name: 'Lola Karimova', phone: '+998 90 111 22 33', telegram: '@lola_k' })
      .expect(201);
    let people = (await pull(o.s)).body.changes.connections;
    expect(people).toHaveLength(1);
    expectSchema('Connection', people[0]);
    expect(people[0].contacts.map((e: Entry) => [e.kind, e.value])).toEqual([
      ['phone', '+998901112233'],
      ['telegram', '@lola_k'],
    ]);
    expect(people[0]).toMatchObject({ phone: '+998901112233', telegram: '@lola_k' });
    await http().delete(`/api/public/sharebacks/${created.body.shareBackId}`).set('X-Removal-Token', created.body.removalToken).expect(204);

    // An existing connection known only by WhatsApp: the same number dedupes, the Telegram is added.
    const known = connection({ fullName: 'Sardor', phone: '', telegram: '', contacts: [entry('whatsapp', '+998 90 765 43 21', 'connections')] });
    await push(o.s, { connections: [known] });
    const merged = await http()
      .post(`/api/public/cards/${o.slug}/shareback`)
      .set('X-Forwarded-For', '203.0.113.72')
      .send({ platform: 'ios', name: 'Sardor', phone: '+998907654321', telegram: '@sardor_new' })
      .expect(201);
    people = (await pull(o.s)).body.changes.connections.filter((c: { deletedAt?: string }) => !c.deletedAt);
    const sardor = people.find((c: { id: string }) => c.id === known.id);
    expect(sardor.contacts.map((e: Entry) => [e.kind, e.value])).toEqual([
      ['whatsapp', '+998 90 765 43 21'],
      ['phone', '+998907654321'],
      ['telegram', '@sardor_new'],
    ]);
    await http().delete(`/api/public/sharebacks/${merged.body.shareBackId}`).set('X-Removal-Token', merged.body.removalToken).expect(204);
    const after = (await pull(o.s)).body.changes.connections.find((c: { id: string }) => c.id === known.id);
    expect(after.contacts.map((e: Entry) => e.kind)).toEqual(['whatsapp']);
    expect(after).toMatchObject({ phone: '', telegram: '' });
  });

  // ───────────────────────────── Rows from before the list ─────────────────────────────

  it('rows stored before the list read as the list built from their legacy columns', async () => {
    const s = await signIn(app, randomUUID(), 'Old Row');
    const extra = { id: randomUUID(), label: 'home', value: '+998 71 300 00 00', privacy: 'public' };
    const p = profile({ fullName: 'Old Row', phoneLabel: 'work', additionalPhones: [extra] });
    const c = card({ design: { ...design, visibleFields: ['phone', 'email', 'telegram'] } });
    const conn = connection({ website: 'acme.uz' });
    const res = await push(s, { profile: p, cards: [c], connections: [conn] });
    const slug = res.body.records.cards[0].slug as string;
    // As the migration leaves them: legacy columns, empty list.
    await prisma.profile.update({ where: { userId: s.userId }, data: { contacts: [] } });
    await prisma.connection.update({ where: { id: conn.id }, data: { contacts: [] } });

    const pulled = (await pull(s)).body.changes;
    expectSchema('Profile', pulled.profile);
    expect(pulled.profile.contacts).toEqual([
      { id: PRIMARY.phone, kind: 'phone', label: 'work', value: '+998901234567', privacy: 'public' },
      { ...extra, kind: 'phone' },
      { id: PRIMARY.email, kind: 'email', label: null, value: 'kamola@metly.test', privacy: 'connections' },
      { id: PRIMARY.telegram, kind: 'telegram', label: null, value: '@kamola', privacy: 'private' },
    ]);
    expect(pulled.profile.contactFields.map((f: { kind: string; value: string }) => [f.kind, f.value])).toEqual([
      ['phone', '+998901234567'],
      ['email', 'kamola@metly.test'],
      ['telegram', '@kamola'],
      ['website', ''],
      ['linkedin', ''],
    ]);
    const oldConnection = pulled.connections.find((x: { id: string }) => x.id === conn.id);
    expectSchema('Connection', oldConnection);
    expect(oldConnection.contacts.map((e: Entry) => [e.id, e.kind, e.value])).toEqual([
      [PRIMARY.phone, 'phone', '+998907654321'],
      [PRIMARY.telegram, 'telegram', '@sardor'],
      [PRIMARY.website, 'website', 'acme.uz'],
    ]);

    const json = await http().get(`/api/public/cards/${slug}`).expect(200);
    expectSchema('PublicCard', json.body);
    expect(json.body.contacts.map((e: Entry) => e.value)).toEqual(['+998901234567', '+998 71 300 00 00']);
    expect(json.body.phoneLabel).toBe('work');

    // A card written by a new app can point at the fixed ids; an older app's next push keeps them.
    const pick = { ...c, design: { ...design, visibleContacts: [PRIMARY.phone] }, updatedAt: now(1000) };
    await push(s, { cards: [pick], profile: { ...p, jobTitle: 'Edited on an old build', updatedAt: now(1000) } });
    const stored = await prisma.profile.findUniqueOrThrow({ where: { userId: s.userId } });
    expect((stored.contacts as Entry[]).map((e) => e.id)).toEqual([PRIMARY.phone, extra.id, PRIMARY.email, PRIMARY.telegram]);
    expect((await http().get(`/api/public/cards/${slug}`).expect(200)).body.contacts.map((e: Entry) => e.id)).toEqual([PRIMARY.phone]);
  });
});
