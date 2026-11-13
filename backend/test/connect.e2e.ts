import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it, type MockInstance, vi } from 'vitest';
import { ConnectExpiryService } from '../src/connect/connect-expiry.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { PushService } from '../src/push/push.service';
import { RealtimeService } from '../src/realtime/realtime.service';
import { expectSchema } from './contract';
import { card, connection, createApp, event, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

interface Person {
  s: Session;
  userId: string;
  cardId: string;
  slug: string;
  name: string;
}

describe('connect', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;
  let realtime: MockInstance<RealtimeService['publish']>;
  let push: MockInstance<PushService['notify']>;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(async () => {
    await resetRateLimits(app);
    vi.restoreAllMocks();
    realtime = vi.spyOn(app.get(RealtimeService), 'publish');
    push = vi.spyOn(app.get(PushService), 'notify');
  });

  const http = () => request(app.getHttpServer());

  /** A signed-in user with a profile (phone public, email connections, telegram private) and a card. */
  const person = async (name: string, overrides: Record<string, unknown> = {}): Promise<Person> => {
    const s = await signIn(app, randomUUID(), name);
    await http().put('/v1/me/profile').set(s.auth).send(profile({ fullName: name, ...overrides })).expect(200);
    const c = card();
    const res = await http().put(`/v1/cards/${c.id}`).set(s.auth).send(c).expect(200);
    return { s, userId: s.userId, cardId: c.id, slug: res.body.slug, name };
  };

  const session = async (p: Person) => {
    const res = await http().post('/v1/connect/sessions').set(p.s.auth).send({ cardId: p.cardId, method: 'nearby' }).expect(201);
    expectSchema('ConnectSession', res.body);
    return res.body as { sessionId: string; discoveryToken: string; expiresAt: string };
  };

  const send = (from: Person, body: Record<string, unknown>) =>
    http()
      .post('/v1/connect/requests')
      .set(from.s.auth)
      .set('Idempotency-Key', randomUUID())
      .send({ cardId: from.cardId, method: 'scan', ...body });

  const accept = (p: Person, id: string) => http().post(`/v1/connect/requests/${id}/accept`).set(p.s.auth).send({ cardId: p.cardId });
  const getRequest = (p: Person, id: string) => http().get(`/v1/connect/requests/${id}`).set(p.s.auth);
  const pull = (p: Person, since?: string) =>
    http()
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(p.s.auth)
      .expect(200);
  const expire = async (requestId: string) => {
    await prisma.connectRequest.update({ where: { id: requestId }, data: { expiresAt: new Date(Date.now() - 1000) } });
    return app.get(ConnectExpiryService).publishExpired();
  };
  const realtimeTo = (userId: string, type: string) => realtime.mock.calls.filter((c) => c[0] === userId && c[1] === type).map((c) => c[2] as any);
  const pushesTo = (userId: string) => push.mock.calls.filter((c) => c[0] === userId).map((c) => c[1] as any);

  it('opens a session and resolves peers with public fields only, skipping self, unknown and ended tokens', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const sa = await session(a);
    const sb = await session(b);
    expect(sa.discoveryToken.length).toBeGreaterThanOrEqual(22);
    expect(sa.discoveryToken).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(new Date(sa.expiresAt).getTime() - Date.now()).toBeGreaterThan(9 * 60_000);

    const res = await http().get('/v1/connect/peers').query({ tokens: `${sa.discoveryToken},nope,${sb.discoveryToken}` }).set(b.s.auth).expect(200);
    expectSchema('NearbyPeerPage', res.body);
    expect(res.body.items).toHaveLength(1);
    const peer = res.body.items[0];
    expect(peer).toMatchObject({ token: sa.discoveryToken, userId: a.userId, fullName: 'Aziza Karimova' });
    expect(peer.card.fields).toEqual([{ kind: 'phone', value: '+998901234567', privacy: 'public' }]);

    await http().delete(`/v1/connect/sessions/${sa.sessionId}`).set(a.s.auth).expect(204);
    const after = await http().get('/v1/connect/peers').query({ tokens: sa.discoveryToken }).set(b.s.auth).expect(200);
    expect(after.body.items).toEqual([]);
  });

  it('validates sessions and peer lookups', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const bad = await http().post('/v1/connect/sessions').set(a.s.auth).send({ cardId: b.cardId, method: 'nearby' }).expect(422);
    expectSchema('Error', bad.body);
    const tokens = Array.from({ length: 51 }, (_, i) => `t${i}`).join(',');
    await http().get('/v1/connect/peers').query({ tokens }).set(a.s.auth).expect(422);
    const none = await send(a, { toToken: 'x', toUserId: b.userId }).expect(422);
    expect(none.body.code).toBe('validation_failed');
  });

  it('never resolves hidden or blocked users', async () => {
    const hidden = await person('Hilola Hidden', { privacySettings: { findByEmail: true, showInNearby: false, shareAnalytics: true } });
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const sh = await session(hidden);
    const sa = await session(a);
    const sb = await session(b);

    const peers = await http().get('/v1/connect/peers').query({ tokens: `${sh.discoveryToken},${sa.discoveryToken}` }).set(b.s.auth).expect(200);
    expect(peers.body.items.map((p: { userId: string }) => p.userId)).toEqual([a.userId]);
    const toHidden = await send(b, { toToken: sh.discoveryToken, method: 'nearby' }).expect(404);
    expect(toHidden.body.code).toBe('peer_unavailable');

    await http().post('/v1/me/blocks').set(a.s.auth).send({ userId: b.userId }).expect(200);
    const fromB = await http().get('/v1/connect/peers').query({ tokens: sa.discoveryToken }).set(b.s.auth).expect(200);
    expect(fromB.body.items).toEqual([]);
    const fromA = await http().get('/v1/connect/peers').query({ tokens: sb.discoveryToken }).set(a.s.auth).expect(200);
    expect(fromA.body.items).toEqual([]);
  });

  it('swaps cards via a Nearby token: a mutual connection on both sides, in both pulls', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const cursorA = (await pull(a)).body.cursor;
    const cursorB = (await pull(b)).body.cursor;
    const sa = await session(a);

    const sent = await send(b, { toToken: sa.discoveryToken, method: 'nearby', eventName: 'ICT Week', place: 'Hall B' }).expect(201);
    expectSchema('ConnectRequest', sent.body);
    expect(sent.body).toMatchObject({ direction: 'outgoing', status: 'pending', method: 'nearby', myCardId: b.cardId, eventName: 'ICT Week' });
    const lifetime = new Date(sent.body.expiresAt).getTime() - new Date(sent.body.createdAt).getTime();
    expect(lifetime).toBe(60_000);
    expect(sent.body.peer.userId).toBe(a.userId);

    // The recipient is told (realtime + push) and sees the requester's public card.
    const received = realtimeTo(a.userId, 'connect.request.received');
    expect(received).toHaveLength(1);
    expectSchema('ConnectRequest', received[0]);
    expect(received[0]).toMatchObject({ id: sent.body.id, direction: 'incoming', status: 'pending' });
    expect(pushesTo(a.userId)).toEqual([
      expect.objectContaining({
        type: 'connect_request',
        text: { id: 'connectRequest', params: { name: 'Bobur', eventName: 'ICT Week' } },
        category: 'CONNECT_REQUEST',
        data: { requestId: sent.body.id },
      }),
    ]);
    const incoming = await http().get('/v1/connect/requests').query({ direction: 'incoming', status: 'pending' }).set(a.s.auth).expect(200);
    expectSchema('ConnectRequestPage', incoming.body);
    expect(incoming.body.items.map((r: { id: string }) => r.id)).toEqual([sent.body.id]);
    expect(incoming.body.items[0].peer.card.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone']);

    const res = await accept(a, sent.body.id).expect(200);
    expectSchema('ConnectAcceptResponse', res.body);
    expect(res.body.request).toMatchObject({ direction: 'incoming', status: 'accepted', myCardId: a.cardId });
    const connA = res.body.connection;
    expect(connA).toMatchObject({ remoteUserId: b.userId, fullName: 'Bobur Aliev', source: 'nearby', mySharedCardId: a.cardId, isBlocked: false });
    expect(connA.email).toBe('kamola@metly.test'); // Connections-level field, filled from the card
    expect(connA.telegram).toBe(''); // Private never leaves the owner
    expect(connA.theirCard.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);
    expect(connA.context).toMatchObject({ eventName: 'ICT Week', place: 'Hall B' });

    // The requester learns over realtime, with their own connection.
    const updated = realtimeTo(b.userId, 'connect.request.updated');
    expect(updated).toHaveLength(1);
    expectSchema('ConnectRequestUpdatedData', updated[0]);
    expect(updated[0].request).toMatchObject({ id: sent.body.id, direction: 'outgoing', status: 'accepted' });
    expect(updated[0].request.peer.card.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);
    expect(updated[0].connection).toMatchObject({ remoteUserId: a.userId, source: 'nearby', mySharedCardId: b.cardId });
    expect(pushesTo(b.userId)).toEqual([expect.objectContaining({ type: 'connect_result', data: expect.objectContaining({ requestId: sent.body.id }) })]);

    const rows = await prisma.connection.findMany({ where: { userId: { in: [a.userId, b.userId] } } });
    expect(rows).toHaveLength(2);
    expect(rows.every((r) => r.isMutual)).toBe(true);

    const deltaA = await pull(a, cursorA);
    expectSchema('SyncPullResponse', deltaA.body);
    expect(deltaA.body.changes.connections.map((c: { id: string }) => c.id)).toEqual([connA.id]);
    expect(deltaA.body.changes.connectRequests).toEqual([expect.objectContaining({ id: sent.body.id, status: 'accepted' })]);
    const deltaB = await pull(b, cursorB);
    expectSchema('SyncPullResponse', deltaB.body);
    expect(deltaB.body.changes.connections.map((c: { remoteUserId: string }) => c.remoteUserId)).toEqual([a.userId]);
    expect(deltaB.body.changes.connectRequests).toEqual([expect.objectContaining({ id: sent.body.id, status: 'accepted', direction: 'outgoing' })]);

    const again = await accept(a, sent.body.id).expect(409);
    expect(again.body.code).toBe('request_expired');
    // Only the recipient may accept; strangers do not learn the request exists.
    await accept(b, sent.body.id).expect(404);
    const stranger = await person('Sanjar Stranger');
    await getRequest(stranger, sent.body.id).expect(404);
  });

  it('keeps a decline invisible to the requester until expiry, then publishes expired', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const sent = await send(b, { toUserId: a.userId }).expect(201);
    expect(new Date(sent.body.expiresAt).getTime() - new Date(sent.body.createdAt).getTime()).toBe(7 * 86_400_000);
    const cursorB = (await pull(b)).body.cursor;

    const declined = await http().post(`/v1/connect/requests/${sent.body.id}/decline`).set(a.s.auth).expect(200);
    expectSchema('ConnectRequest', declined.body);
    expect(declined.body.status).toBe('declined');
    expect(realtimeTo(b.userId, 'connect.request.updated')).toEqual([]);

    const seen = await getRequest(b, sent.body.id).expect(200);
    expect(seen.body.status).toBe('pending');
    expect(seen.body.respondedAt).toBeUndefined();
    const pending = await http().get('/v1/connect/requests').query({ status: 'pending' }).set(b.s.auth).expect(200);
    expect(pending.body.items.map((r: { id: string }) => r.id)).toContain(sent.body.id);
    const declinedList = await http().get('/v1/connect/requests').query({ status: 'declined' }).set(b.s.auth).expect(200);
    expect(declinedList.body.items).toEqual([]);
    expect((await pull(b, cursorB)).body.changes.connectRequests).toEqual([]);

    await http().post(`/v1/connect/requests/${sent.body.id}/decline`).set(a.s.auth).expect(409);

    expect(await expire(sent.body.id)).toBeGreaterThanOrEqual(1);
    const expired = await getRequest(b, sent.body.id).expect(200);
    expect(expired.body.status).toBe('expired');
    const notice = realtimeTo(b.userId, 'connect.request.updated');
    expect(notice).toHaveLength(1);
    expect(notice[0].request).toMatchObject({ id: sent.body.id, status: 'expired' });
    expect((await pull(b, cursorB)).body.changes.connectRequests).toEqual([expect.objectContaining({ id: sent.body.id, status: 'expired' })]);
    expect((await getRequest(a, sent.body.id).expect(200)).body.status).toBe('declined');
    // Published once.
    expect(await app.get(ConnectExpiryService).publishExpired()).toBe(0);
  });

  it('suppresses requests between blocked users: never delivered, never auto-accepted', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    await http().post('/v1/me/blocks').set(a.s.auth).send({ userId: b.userId }).expect(200);
    const cursorA = (await pull(a)).body.cursor;

    const sent = await send(b, { toSlug: a.slug }).expect(201);
    expect(sent.body.status).toBe('pending');
    const deferred = await send(b, { toSlug: a.slug, method: 'deferred' }).expect(201);
    expect(deferred.body.status).toBe('pending');

    expect(realtimeTo(a.userId, 'connect.request.received')).toEqual([]);
    expect(pushesTo(a.userId)).toEqual([]);
    const list = await http().get('/v1/connect/requests').set(a.s.auth).expect(200);
    expect(list.body.items).toEqual([]);
    await getRequest(a, sent.body.id).expect(404);
    await accept(a, sent.body.id).expect(404);
    expect((await pull(a, cursorA)).body.changes.connectRequests).toEqual([]);
    expect(await prisma.connection.count({ where: { userId: { in: [a.userId, b.userId] } } })).toBe(0);

    await expire(sent.body.id);
    expect((await getRequest(b, sent.body.id).expect(200)).body.status).toBe('expired');
  });

  it('accepts deferred-link requests immediately', async () => {
    const owner = await person('Aziza Karimova');
    const installer = await person('Bobur Aliev');
    const res = await send(installer, { toSlug: owner.slug, method: 'deferred' }).expect(201);
    expectSchema('ConnectRequest', res.body);
    expect(res.body).toMatchObject({ status: 'accepted', direction: 'outgoing' });
    expect(res.body.peer.card.cardName).toBe('Work');

    const mine = await prisma.connection.findFirstOrThrow({ where: { userId: installer.userId } });
    const theirs = await prisma.connection.findFirstOrThrow({ where: { userId: owner.userId } });
    expect(mine).toMatchObject({ remoteUserId: owner.userId, source: 'deferredLink', isMutual: true, mySharedCardId: installer.cardId });
    expect(theirs).toMatchObject({ remoteUserId: installer.userId, source: 'deferredLink', isMutual: true, mySharedCardId: owner.cardId });
    const updated = realtimeTo(installer.userId, 'connect.request.updated');
    expect(updated).toHaveLength(1);
    expectSchema('ConnectRequestUpdatedData', updated[0]);
    expect(pushesTo(owner.userId)).toEqual([expect.objectContaining({ type: 'connect_result' })]);
  });

  it('reuses an existing connection, keeps the old meeting and settles other pending requests', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    // A added Bobur by scanning earlier (one-sided) and is now at an active event.
    const existing = connection({ remoteUserId: b.userId, fullName: 'Bobur', phone: '', email: '', context: { eventName: 'Old meetup', metAt: now(-86_400_000) } });
    await http().put(`/v1/connections/${existing.id}`).set(a.s.auth).send(existing).expect(200);
    const ev = event({ name: 'ICT Week', place: 'Expo Center', city: 'Tashkent' });
    await http().put(`/v1/events/${ev.id}`).set(a.s.auth).send(ev).expect(200);

    const fromA = await send(a, { toUserId: b.userId }).expect(201);
    const fromB = await send(b, { toSlug: a.slug, eventName: 'Somewhere else' }).expect(201);

    const res = await accept(a, fromB.body.id).expect(200);
    expectSchema('ConnectAcceptResponse', res.body);
    const conn = res.body.connection;
    expect(conn.id).toBe(existing.id);
    expect(conn).toMatchObject({ fullName: 'Bobur Aliev', phone: '+998901234567', email: 'kamola@metly.test', source: 'scanQR', eventId: ev.id });
    expect(conn.context).toMatchObject({ eventId: ev.id, eventName: 'ICT Week', place: 'Expo Center', city: 'Tashkent' });
    expect(conn.previousMeetings).toEqual([expect.objectContaining({ eventName: 'Old meetup' })]);
    expect(await prisma.connection.count({ where: { userId: a.userId, deletedAt: null } })).toBe(1);
    expect((await prisma.connection.findUniqueOrThrow({ where: { id: existing.id } })).isMutual).toBe(true);

    // B has no active event: their side uses what the request carried.
    const bConn = await prisma.connection.findFirstOrThrow({ where: { userId: b.userId } });
    expect(bConn.context).toMatchObject({ eventName: 'Somewhere else', eventId: null });

    // A's own request to B is settled too (README rule).
    const settled = await getRequest(a, fromA.body.id).expect(200);
    expect(settled.body.status).toBe('accepted');
    expect((await getRequest(b, fromA.body.id).expect(200)).body.status).toBe('accepted');
  });

  it('cancels: explicitly, and when a new live request replaces the previous one', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const c = await person('Sardor Rashidov');
    const sa = await session(a);
    const sc = await session(c);

    const first = await send(b, { toToken: sa.discoveryToken, method: 'nearby' }).expect(201);
    const second = await send(b, { toToken: sc.discoveryToken, method: 'tapPhones' }).expect(201);
    expect((await getRequest(a, first.body.id).expect(200)).body.status).toBe('cancelled');
    expect(realtimeTo(a.userId, 'connect.request.updated')[0].request).toMatchObject({ id: first.body.id, status: 'cancelled' });

    const cancelled = await http().post(`/v1/connect/requests/${second.body.id}/cancel`).set(b.s.auth).expect(200);
    expectSchema('ConnectRequest', cancelled.body);
    expect(cancelled.body.status).toBe('cancelled');
    const toC = realtimeTo(c.userId, 'connect.request.updated');
    expect(toC).toHaveLength(1);
    expect(toC[0].request).toMatchObject({ id: second.body.id, direction: 'incoming', status: 'cancelled' });
    await http().post(`/v1/connect/requests/${second.body.id}/cancel`).set(c.s.auth).expect(404);
    await http().post(`/v1/connect/requests/${second.body.id}/cancel`).set(b.s.auth).expect(409);
    await accept(c, second.body.id).expect(409);
  });

  it('rejects unavailable peers', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    expect((await send(b, { toSlug: 'nobody-zzzz' }).expect(404)).body.code).toBe('peer_unavailable');
    expect((await send(b, { toToken: 'expired-or-unknown' }).expect(404)).body.code).toBe('peer_unavailable');
    expect((await send(b, { toUserId: randomUUID() }).expect(404)).body.code).toBe('peer_unavailable');
    await http().patch('/v1/me/settings').set(a.s.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
    expect((await send(b, { toSlug: a.slug }).expect(404)).body.code).toBe('peer_unavailable');
    await send(b, { toUserId: b.userId }).expect(422);
  });

  it('shows public profiles with Connections fields only after a mutual connect', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const view = (viewer: Person, slug = a.slug) => http().get(`/v1/public-profiles/${slug}`).set(viewer.s.auth);

    const stranger = await view(b).expect(200);
    expectSchema('PublicCard', stranger.body);
    expect(stranger.body).toMatchObject({ slug: a.slug, status: 'available', cardName: 'Work', url: `https://metly.test/c/${a.slug}` });
    expect(stranger.body.owner).toMatchObject({ userId: a.userId, fullName: 'Aziza Karimova', firstName: 'Aziza' });
    expect(stranger.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone']);
    expect(stranger.body.viewer).toEqual({ isSelf: false, isConnected: false });

    // One-sided connections (either side adding the other) never unlock Connections fields.
    const oneSidedA = connection({ remoteUserId: b.userId });
    await http().put(`/v1/connections/${oneSidedA.id}`).set(a.s.auth).send(oneSidedA).expect(200);
    const oneSidedB = connection({ remoteUserId: a.userId });
    await http().put(`/v1/connections/${oneSidedB.id}`).set(b.s.auth).send(oneSidedB).expect(200);
    const oneSided = await view(b).expect(200);
    expect(oneSided.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone']);
    expect(oneSided.body.viewer).toEqual({ isSelf: false, isConnected: false, connectionId: oneSidedB.id });

    const sent = await send(b, { toSlug: a.slug }).expect(201);
    await accept(a, sent.body.id).expect(200);
    const mutual = await view(b).expect(200);
    expectSchema('PublicCard', mutual.body);
    expect(mutual.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);
    expect(mutual.body.viewer).toEqual({ isSelf: false, isConnected: true, connectionId: oneSidedB.id });

    const self = await view(a).expect(200);
    expect(self.body.viewer).toEqual({ isSelf: true, isConnected: false });
    expect(self.body.fields.map((f: { kind: string }) => f.kind)).toEqual(['phone', 'email']);

    await view(b, 'unknown-zzzz').expect(404);
    await http().post('/v1/me/blocks').set(a.s.auth).send({ userId: b.userId }).expect(200);
    await view(b).expect(404);
    await http().delete(`/v1/me/blocks/${b.userId}`).set(a.s.auth).expect(204);
    await view(b).expect(200);

    await http().patch('/v1/me/settings').set(a.s.auth).send({ linksPaused: true, updatedAt: now(1000) }).expect(200);
    const paused = await view(b).expect(200);
    expectSchema('PublicCard', paused.body);
    expect(paused.body).toEqual({ slug: a.slug, status: 'paused' });

    const c = await person('Sardor Rashidov');
    await http().delete(`/v1/cards/${c.cardId}`).set(c.s.auth).expect(204);
    const deleted = await view(b, c.slug).expect(200);
    expect(deleted.body).toEqual({ slug: c.slug, status: 'deleted' });
  });

  it('blocks and unblocks via a connection, keeping it in sync', async () => {
    const a = await person('Aziza Karimova');
    const b = await person('Bobur Aliev');
    const conn = connection({ remoteUserId: b.userId, fullName: 'Bobur A.' });
    await http().put(`/v1/connections/${conn.id}`).set(a.s.auth).send(conn).expect(200);
    const cursor = (await pull(a)).body.cursor;

    const blocked = await http().post(`/v1/connections/${conn.id}/block`).set(a.s.auth).set('Idempotency-Key', randomUUID()).expect(200);
    expectSchema('Connection', blocked.body);
    expect(blocked.body.isBlocked).toBe(true);
    expect((await pull(a, cursor)).body.changes.connections).toEqual([expect.objectContaining({ id: conn.id, isBlocked: true })]);

    const list = await http().get('/v1/me/blocks').set(a.s.auth).expect(200);
    expectSchema('BlockPage', list.body);
    expect(list.body.items).toEqual([expect.objectContaining({ userId: b.userId, connectionId: conn.id, fullName: 'Bobur A.' })]);
    // Blocking again is idempotent.
    const again = await http().post('/v1/me/blocks').set(a.s.auth).send({ connectionId: conn.id }).expect(200);
    expectSchema('Block', again.body);
    expect((await http().get('/v1/me/blocks').set(a.s.auth).expect(200)).body.items).toHaveLength(1);

    await http().delete(`/v1/me/blocks/${b.userId}`).set(a.s.auth).expect(204);
    expect((await http().get('/v1/me/blocks').set(a.s.auth).expect(200)).body.items).toEqual([]);
    expect((await prisma.connection.findUniqueOrThrow({ where: { id: conn.id } })).isBlocked).toBe(false);

    // A connection blocked on a device (synced) counts as a block too.
    await http()
      .put(`/v1/connections/${conn.id}`)
      .set(a.s.auth)
      .send({ ...conn, isBlocked: true, updatedAt: now(60_000) })
      .expect(200);
    const synced = await http().get('/v1/me/blocks').set(a.s.auth).expect(200);
    expectSchema('BlockPage', synced.body);
    expect(synced.body.items).toEqual([expect.objectContaining({ userId: b.userId, connectionId: conn.id })]);
    await http().get(`/v1/public-profiles/${a.slug}`).set(b.s.auth).expect(404);

    await http().post('/v1/me/blocks').set(a.s.auth).send({}).expect(422);
    await http().post('/v1/me/blocks').set(a.s.auth).send({ userId: a.userId }).expect(422);
  });
});
