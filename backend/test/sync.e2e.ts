import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PrismaService } from '../src/prisma/prisma.service';
import { expectSchema } from './contract';
import { card, connection, createApp, event, followUp, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

describe('sync', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  const push = (s: Session, changes: Record<string, unknown>, key?: string) => {
    const r = request(app.getHttpServer()).post('/v1/sync/push').set(s.auth);
    if (key) r.set('Idempotency-Key', key);
    return r.send({ deviceId: 'device-1', changes });
  };
  const pull = (s: Session, since?: string, limit?: number) =>
    request(app.getHttpServer())
      .get('/v1/sync')
      .query({ ...(since ? { since } : {}), ...(limit ? { limit } : {}) })
      .set(s.auth);

  it('applies a first push, assigns the slug and returns canonical records', async () => {
    const s = await signIn(app);
    const p = profile({ fullName: 'Камола Юсупова' });
    const c = card();
    const res = await push(s, { profile: p, cards: [c] }).expect(200);
    expectSchema('SyncPushResponse', res.body);
    expect(res.body.results).toEqual([
      { type: 'profile', id: p.id, status: 'applied' },
      { type: 'card', id: c.id, status: 'applied' },
    ]);
    const stored = res.body.records.cards[0];
    expect(stored.slug).toMatch(/^kamola-[a-z2-9]{4}$/);
    expect(stored.url).toBe(`https://metly.test/c/${stored.slug}`);
    expect(stored.publishState).toBe('published');
    expect(stored.isPaused).toBe(false);
    expect(stored.stats).toEqual({ views: 0, saves: 0, shareBacks: 0, scans: 0 });
  });

  it('pulls a full snapshot, then only what changed after the cursor', async () => {
    const s = await signIn(app);
    const p = profile();
    const c = card();
    await push(s, { profile: p, cards: [c] }).expect(200);

    const full = await pull(s).expect(200);
    expectSchema('SyncPullResponse', full.body);
    expect(full.body.changes.profile.id).toBe(p.id);
    expect(full.body.changes.cards.map((x: { id: string }) => x.id)).toEqual([c.id]);
    expect(full.body.hasMore).toBe(false);
    expect(full.body.entitlement.plan).toBe('free');

    const empty = await pull(s, full.body.cursor).expect(200);
    expect(empty.body.changes.cards).toEqual([]);
    expect(empty.body.cursor).toBe(full.body.cursor);

    const edited = { ...c, name: 'Personal', updatedAt: now(1000) };
    await push(s, { cards: [edited] }).expect(200);
    const delta = await pull(s, full.body.cursor).expect(200);
    expect(delta.body.changes.cards).toHaveLength(1);
    expect(delta.body.changes.cards[0].name).toBe('Personal');
    expect(delta.body.changes.profile).toBeUndefined();
  });

  it('pages by sequence with hasMore', async () => {
    const s = await signIn(app);
    await push(s, { profile: profile(), cards: [card(), card({ sortOrder: 1 })] }).expect(200);
    const first = await pull(s, undefined, 2).expect(200);
    expect(first.body.hasMore).toBe(true);
    const second = await pull(s, first.body.cursor, 2).expect(200);
    expect(second.body.hasMore).toBe(false);
    const ids = [first.body.changes.profile?.id, ...first.body.changes.cards.map((c: { id: string }) => c.id), ...second.body.changes.cards.map((c: { id: string }) => c.id)].filter(Boolean);
    expect(ids).toHaveLength(3);
  });

  it('keeps the newer write (LWW) and returns the stored record as stale', async () => {
    const s = await signIn(app);
    const c = card({ updatedAt: now(10_000) });
    await push(s, { profile: profile(), cards: [c] }).expect(200);
    const older = { ...c, name: 'Older', updatedAt: now() };
    const res = await push(s, { cards: [older] }).expect(200);
    expect(res.body.results[0].status).toBe('stale');
    expect(res.body.records.cards[0].name).toBe('Work');
  });

  it('rejects one invalid record without failing the batch', async () => {
    const s = await signIn(app);
    const good = card();
    const res = await push(s, { profile: profile(), cards: [{ id: randomUUID(), name: 42 }, good] }).expect(200);
    expect(res.body.results[1].status).toBe('rejected');
    expect(res.body.results[1].error.code).toBe('validation_failed');
    expect(res.body.results[2]).toEqual({ type: 'card', id: good.id, status: 'applied' });
  });

  it('enforces the Free limits per record', async () => {
    const s = await signIn(app);
    const res = await push(s, {
      profile: profile(),
      cards: [card(), card({ sortOrder: 1 }), card({ sortOrder: 2 }), card({ design: { ...card().design, palette: 'ocean' } })],
      events: [event(), event()],
      followUps: Array.from({ length: 6 }, () => followUp()),
    }).expect(200);
    const statuses = res.body.results.map((r: { status: string; error?: { code: string; details?: Record<string, string> } }) => [r.status, r.error?.code, r.error?.details?.limit]);
    expect(statuses.slice(1, 5)).toEqual([
      ['applied', undefined, undefined],
      ['applied', undefined, undefined],
      ['rejected', 'plan_limit_reached', 'cards'],
      ['rejected', 'plan_limit_reached', 'cards'],
    ]);
    expect(statuses.slice(5, 7)).toEqual([
      ['applied', undefined, undefined],
      ['rejected', 'plan_limit_reached', 'activeEvents'],
    ]);
    expect(statuses.slice(7).filter((x: unknown[]) => x[0] === 'rejected')).toEqual([['rejected', 'plan_limit_reached', 'openFollowUps']]);
  });

  it('rejects Pro palettes and templates on the Free plan', async () => {
    const s = await signIn(app);
    const res = await push(s, { profile: profile(), cards: [card({ design: { ...card().design, template: 'editorial' } })] }).expect(200);
    expect(res.body.results[1].error.code).toBe('pro_required');
  });

  it('tombstones a card, retires its slug and delivers the tombstone in the next pull', async () => {
    const s = await signIn(app);
    const c = card();
    const first = await push(s, { profile: profile(), cards: [c] }).expect(200);
    const slug = first.body.records.cards[0].slug;
    const cursor = (await pull(s).expect(200)).body.cursor;

    const res = await push(s, { tombstones: [{ type: 'card', id: c.id, deletedAt: now(1000) }] }).expect(200);
    expect(res.body.results[0].status).toBe('applied');
    const delta = await pull(s, cursor).expect(200);
    expect(delta.body.changes.tombstones).toEqual([{ type: 'card', id: c.id, deletedAt: expect.any(String) }]);
    expect(await prisma.slug.findUnique({ where: { slug } })).not.toBeNull();

    // Full snapshots leave tombstones out.
    const full = await pull(s).expect(200);
    expect(full.body.changes.tombstones).toEqual([]);
    expect(full.body.changes.cards).toEqual([]);
  });

  it('keeps a live record that is newer than the tombstone', async () => {
    const s = await signIn(app);
    const c = card({ updatedAt: now(60_000) });
    await push(s, { profile: profile(), cards: [c] }).expect(200);
    const res = await push(s, { tombstones: [{ type: 'card', id: c.id, deletedAt: now() }] }).expect(200);
    expect(res.body.results[0].status).toBe('stale');
    expect(res.body.records.cards[0].id).toBe(c.id);
  });

  it('cascades a deleted connection to its follow-ups', async () => {
    const s = await signIn(app);
    const conn = connection();
    const f = followUp({ connectionId: conn.id });
    await push(s, { connections: [conn], followUps: [f] }).expect(200);
    const res = await push(s, { tombstones: [{ type: 'connection', id: conn.id, deletedAt: now(1000) }] }).expect(200);
    expect(res.body.records.tombstones.map((t: { type: string }) => t.type).sort()).toEqual(['connection', 'followUp']);
  });

  it('merges a second connection to the same Tanishly user and re-points its follow-ups', async () => {
    const s = await signIn(app);
    const remoteUserId = randomUUID();
    const original = connection({ remoteUserId, note: 'Met at the booth' });
    await push(s, { connections: [original] }).expect(200);

    const twin = connection({ remoteUserId, phone: '', email: 'sardor@acme.test', updatedAt: now(5000) });
    const f = followUp({ connectionId: twin.id });
    const res = await push(s, { connections: [twin], followUps: [f] }).expect(200);
    expect(res.body.results[0]).toEqual({ type: 'connection', id: twin.id, status: 'applied' });
    const survivor = res.body.records.connections.find((c: { id: string }) => c.id === original.id);
    expect(survivor.email).toBe('sardor@acme.test');
    expect(survivor.phone).toBe('+998907654321');
    expect(survivor.note).toBe('Met at the booth');
    expect(res.body.records.tombstones).toEqual([{ type: 'connection', id: twin.id, deletedAt: twin.updatedAt }]);
    expect(res.body.records.followUps[0].connectionId).toBe(original.id);
  });

  it('cascades an event rename to tagged connections', async () => {
    const s = await signIn(app);
    const e = event();
    const conn = connection({ eventId: e.id, context: { eventId: e.id, eventName: 'ICT Week', metAt: now() } });
    await push(s, { events: [e], connections: [conn] }).expect(200);
    const renamed = { ...e, name: 'ICT Week 2026', updatedAt: now(5000) };
    const res = await push(s, { events: [renamed] }).expect(200);
    const tagged = res.body.records.connections[0];
    expect(tagged.context.eventName).toBe('ICT Week 2026');
    expect(tagged.updatedAt).toBe(renamed.updatedAt);
  });

  it('pauses every card with Pause All Links', async () => {
    const s = await signIn(app);
    const p = profile();
    await push(s, { profile: p, cards: [card()] }).expect(200);
    const cursor = (await pull(s).expect(200)).body.cursor;
    await push(s, { profile: { ...p, linksPaused: true, updatedAt: now(2000) } }).expect(200);
    const delta = await pull(s, cursor).expect(200);
    expect(delta.body.changes.cards[0].isPaused).toBe(true);
  });

  it('answers 410 cursor_expired for an unknown cursor', async () => {
    const s = await signIn(app);
    const res = await pull(s, 'garbage').expect(410);
    expect(res.body.code).toBe('cursor_expired');
  });

  it('replays a retried push with the same Idempotency-Key and refuses a different body', async () => {
    const s = await signIn(app);
    const key = randomUUID();
    const changes = { profile: profile(), cards: [card()] };
    const a = await push(s, changes, key).expect(200);
    const b = await push(s, changes, key).expect(200);
    expect(b.body).toEqual(a.body);
    const c = await push(s, { cards: [card()] }, key).expect(409);
    expect(c.body.code).toBe('idempotency_conflict');
  });

  it('never lets one user write another user’s record id', async () => {
    const a = await signIn(app);
    const b = await signIn(app);
    const c = card();
    await push(a, { profile: profile(), cards: [c] }).expect(200);
    const res = await push(b, { profile: profile(), cards: [{ ...c, name: 'Hijack', updatedAt: now(10_000) }] }).expect(200);
    expect(res.body.results[1].status).toBe('rejected');
    expect((await prisma.card.findUnique({ where: { id: c.id } }))?.name).toBe('Work');
  });
});
