import type { NestExpressApplication } from '@nestjs/platform-express';
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { expectSchema } from './contract';
import { card, connection, createApp, event, followUp, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

describe('REST records', () => {
  let app: NestExpressApplication;
  beforeAll(async () => {
    app = await createApp();
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  const withProfile = async (): Promise<Session> => {
    const s = await signIn(app);
    await request(app.getHttpServer()).put('/v1/me/profile').set(s.auth).send(profile()).expect(200);
    return s;
  };

  it('creates the profile once and keeps the stored id canonical', async () => {
    const s = await signIn(app);
    const first = profile();
    const a = await request(app.getHttpServer()).put('/v1/me/profile').set(s.auth).send(first).expect(200);
    expectSchema('Profile', a.body);
    const second = profile({ fullName: 'Kamola Y.', updatedAt: now(1000) });
    const b = await request(app.getHttpServer()).put('/v1/me/profile').set(s.auth).send(second).expect(200);
    expect(b.body.id).toBe(first.id);
    expect(b.body.fullName).toBe('Kamola Y.');
    const me = await request(app.getHttpServer()).get('/v1/me').set(s.auth).expect(200);
    expect(me.body.user.profileComplete).toBe(true);
  });

  it('patches settings and pauses links', async () => {
    const s = await withProfile();
    const res = await request(app.getHttpServer())
      .patch('/v1/me/settings')
      .set(s.auth)
      .send({ linksPaused: true, updatedAt: now(1000) })
      .expect(200);
    expectSchema('Settings', res.body);
    expect(res.body.linksPaused).toBe(true);
  });

  it('puts, lists, reorders, duplicates and deletes cards', async () => {
    const s = await withProfile();
    const a = card();
    const put = await request(app.getHttpServer()).put(`/v1/cards/${a.id}`).set(s.auth).send(a).expect(200);
    expectSchema('Card', put.body);
    const b = card({ name: 'Personal', sortOrder: 1 });
    await request(app.getHttpServer()).post(`/v1/cards/${b.id}/publish`).set(s.auth).send(b).expect(200);

    const order = await request(app.getHttpServer()).put('/v1/cards/order').set(s.auth).send({ cardIds: [b.id, a.id] }).expect(200);
    expectSchema('CardPage', order.body);
    expect(order.body.items.map((c: { id: string }) => c.id)).toEqual([b.id, a.id]);

    const dup = await request(app.getHttpServer()).post(`/v1/cards/${a.id}/duplicate`).set(s.auth).send({ newCardId: randomUUID(), name: 'Copy' }).expect(403);
    expect(dup.body.code).toBe('plan_limit_reached');

    const stats = await request(app.getHttpServer()).get(`/v1/cards/${a.id}/stats`).set(s.auth).expect(200);
    expectSchema('CardStats', stats.body);

    await request(app.getHttpServer()).delete(`/v1/cards/${a.id}`).set(s.auth).expect(204);
    await request(app.getHttpServer()).get(`/v1/cards/${a.id}`).set(s.auth).expect(404);
    const list = await request(app.getHttpServer()).get('/v1/cards').set(s.auth).expect(200);
    expect(list.body.items.map((c: { id: string }) => c.id)).toEqual([b.id]);
  });

  it('refuses a body id that differs from the path id', async () => {
    const s = await withProfile();
    const a = card();
    const res = await request(app.getHttpServer()).put(`/v1/cards/${randomUUID()}`).set(s.auth).send(a).expect(422);
    expect(res.body.code).toBe('validation_failed');
  });

  it('ends, resumes and summarises events', async () => {
    const s = await withProfile();
    const e = event();
    await request(app.getHttpServer()).put(`/v1/events/${e.id}`).set(s.auth).send(e).expect(200);
    const c = connection({ eventId: e.id });
    await request(app.getHttpServer()).put(`/v1/connections/${c.id}`).set(s.auth).send(c).expect(200);

    const ended = await request(app.getHttpServer()).post(`/v1/events/${e.id}/end`).set(s.auth).expect(200);
    expectSchema('Event', ended.body);
    expect(ended.body.status).toBe('ended');
    expect(ended.body.endedAt).toBeTruthy();
    const resumed = await request(app.getHttpServer()).post(`/v1/events/${e.id}/resume`).set(s.auth).expect(200);
    expect(resumed.body.status).toBe('active');

    const summary = await request(app.getHttpServer()).get(`/v1/events/${e.id}/summary`).set(s.auth).expect(200);
    expectSchema('EventSummary', summary.body);
    expect(summary.body.people).toBe(1);
    expect(summary.body.unnotedConnectionIds).toEqual([c.id]);
  });

  it('stores follow-ups in bulk all-or-nothing against the Free limit', async () => {
    const s = await withProfile();
    const tooMany = Array.from({ length: 6 }, () => followUp());
    const rejected = await request(app.getHttpServer()).post('/v1/followups/bulk').set(s.auth).send({ items: tooMany }).expect(403);
    expect(rejected.body.code).toBe('plan_limit_reached');
    const list = await request(app.getHttpServer()).get('/v1/followups').set(s.auth).expect(200);
    expect(list.body.items).toEqual([]);

    const ok = await request(app.getHttpServer()).post('/v1/followups/bulk').set(s.auth).send({ items: tooMany.slice(0, 5) }).expect(200);
    expectSchema('FollowUpPage', ok.body);
    expect(ok.body.items).toHaveLength(5);
  });

  it('pages connections with a cursor', async () => {
    const s = await withProfile();
    for (let i = 0; i < 3; i++) {
      const c = connection({ fullName: `Person ${i}` });
      await request(app.getHttpServer()).put(`/v1/connections/${c.id}`).set(s.auth).send(c).expect(200);
    }
    const first = await request(app.getHttpServer()).get('/v1/connections').query({ limit: 2 }).set(s.auth).expect(200);
    expectSchema('ConnectionPage', first.body);
    expect(first.body.items).toHaveLength(2);
    const second = await request(app.getHttpServer()).get('/v1/connections').query({ limit: 2, cursor: first.body.nextCursor }).set(s.auth).expect(200);
    expect(second.body.items).toHaveLength(1);
    expect(second.body.nextCursor).toBeNull();
  });
});
