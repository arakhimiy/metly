import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import sharp from 'sharp';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { ExportService } from '../src/media/export/export.service';
import { MemoryStorage } from '../src/media/storage/memory-storage';
import { StorageService } from '../src/media/storage/storage.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { expectSchema } from './contract';
import { unzip } from './media-helpers';
import { card, connection, createApp, event, followUp, profile, request, resetRateLimits, type Session, signIn } from './helpers';

const jpegWithExif = (width = 2000, height = 1500) =>
  sharp({ create: { width, height, channels: 3, background: { r: 30, g: 120, b: 200 } } })
    .withMetadata({ orientation: 6 })
    .withExif({ IFD0: { Copyright: 'Kamola', Software: 'iPhone' }, IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '41/1 18/1 0/1' } })
    .jpeg()
    .toBuffer();

describe('media without storage, mail or Wallet certificates', () => {
  let app: NestExpressApplication;
  beforeAll(async () => {
    app = await createApp();
  });
  afterAll(() => app.close());

  it('answers 503 for uploads and Wallet passes and keeps exports queued', async () => {
    const s = await signIn(app);
    await request(app.getHttpServer()).put('/v1/me/profile').set(s.auth).send(profile()).expect(200);
    const res = await request(app.getHttpServer())
      .post('/v1/me/profile/photo/upload')
      .set(s.auth)
      .send({ contentType: 'image/jpeg', byteSize: 1000 })
      .expect(503);
    expectSchema('Error', res.body);
    expect(res.body.code).toBe('service_unavailable');

    const c = card();
    await request(app.getHttpServer()).put(`/v1/cards/${c.id}`).set(s.auth).send(c).expect(200);
    const pass = await request(app.getHttpServer()).get(`/v1/cards/${c.id}/wallet-pass`).set(s.auth).expect(503);
    expect(pass.body.code).toBe('service_unavailable');
    expect(pass.body.message).toMatch(/Wallet/);

    await request(app.getHttpServer()).post('/v1/me/export').set(s.auth).expect(202);
    expect(await app.get(ExportService).runOnce()).toBe(0);
    const queued = await app.get(PrismaService).dataExportRequest.findMany({ where: { userId: s.userId } });
    expect(queued).toHaveLength(1);
    expect(queued[0]!.completedAt).toBeNull();
  });
});

describe('media with storage', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;
  let storage: MemoryStorage;

  beforeAll(async () => {
    process.env.METLY_TEST_STORAGE = 'memory';
    process.env.S3_PUBLIC_BASE_URL = 'https://cdn.metly.test';
    process.env.RESEND_API_KEY = 're_test_key';
    app = await createApp();
    prisma = app.get(PrismaService);
    storage = app.get(StorageService).storage as MemoryStorage;
  });
  afterAll(async () => {
    await app.close();
    delete process.env.METLY_TEST_STORAGE;
    delete process.env.S3_PUBLIC_BASE_URL;
    delete process.env.RESEND_API_KEY;
    vi.unstubAllGlobals();
  });
  beforeEach(() => resetRateLimits(app));

  const server = () => app.getHttpServer();

  const withProfile = async (overrides: Record<string, unknown> = {}): Promise<Session> => {
    const s = await signIn(app);
    await request(server()).put('/v1/me/profile').set(s.auth).send(profile(overrides)).expect(200);
    return s;
  };

  /** Ticket → "upload" the bytes to the presigned URL → returns the uploadId. */
  const upload = async (s: Session, bytes: Buffer, kind = 'photo', contentType = 'image/jpeg') => {
    const res = await request(server()).post(`/v1/me/profile/${kind}/upload`).set(s.auth).send({ contentType, byteSize: bytes.length }).expect(200);
    expectSchema('UploadTicket', res.body);
    const key = storage.keyFromPresignedUrl(res.body.uploadUrl);
    await storage.putObject(key, bytes, { contentType });
    return { uploadId: res.body.uploadId as string, key };
  };

  const pull = (s: Session, since?: string) =>
    request(server())
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(s.auth)
      .expect(200);

  it('issues an upload ticket and validates type and size', async () => {
    const s = await withProfile();
    const res = await request(server()).post('/v1/me/profile/photo/upload').set(s.auth).send({ contentType: 'image/png', byteSize: 1234 }).expect(200);
    expectSchema('UploadTicket', res.body);
    expect(res.body).toMatchObject({ method: 'PUT', headers: { 'Content-Type': 'image/png' }, maxBytes: 5_000_000 });
    expect(storage.keyFromPresignedUrl(res.body.uploadUrl)).toBe(`uploads/${s.userId}/${res.body.uploadId}`);
    expect(Date.parse(res.body.expiresAt) - Date.now()).toBeGreaterThan(14 * 60_000);

    const tooBig = await request(server()).post('/v1/me/profile/photo/upload').set(s.auth).send({ contentType: 'image/jpeg', byteSize: 5_000_001 }).expect(413);
    expect(tooBig.body.code).toBe('payload_too_large');
    const gif = await request(server()).post('/v1/me/profile/logo/upload').set(s.auth).send({ contentType: 'image/gif', byteSize: 10 }).expect(415);
    expect(gif.body.code).toBe('unsupported_media_type');
    await request(server()).post('/v1/me/profile/photo/upload').set(s.auth).send({ contentType: 'image/jpeg' }).expect(422);
    await request(server()).post('/v1/me/profile/banner/upload').set(s.auth).send({ contentType: 'image/jpeg', byteSize: 10 }).expect(404);
  });

  it('commits a photo: re-encodes, strips EXIF, bumps seq and updates avatars held by others', async () => {
    const owner = await withProfile();
    const c = card();
    await request(server()).put(`/v1/cards/${c.id}`).set(owner.auth).send(c).expect(200);
    const before = await prisma.card.findUniqueOrThrow({ where: { id: c.id } });

    const holder = await withProfile({ fullName: 'Sardor Rashidov' });
    const held = connection({ remoteUserId: owner.userId, fullName: 'Kamola Yusupova' });
    await request(server()).put(`/v1/connections/${held.id}`).set(holder.auth).send(held).expect(200);
    const ownerCursor = (await pull(owner)).body.cursor;
    const holderCursor = (await pull(holder)).body.cursor;

    const { uploadId, key } = await upload(owner, await jpegWithExif());
    const res = await request(server()).put('/v1/me/profile/photo').set(owner.auth).send({ uploadId }).expect(200);
    expectSchema('Profile', res.body);
    const prefix = `https://cdn.metly.test/public/${owner.userId}/photo-`;
    expect(res.body.photoUrl).toMatch(new RegExp(`^${prefix}[\\w-]+\\.jpg$`));

    // Raw upload gone, public image stored without metadata, rotated and fitted.
    expect(storage.objects.has(key)).toBe(false);
    const publicKey = storage.keyFromPublicUrl(res.body.photoUrl)!;
    const stored = storage.objects.get(publicKey)!;
    expect(stored.contentType).toBe('image/jpeg');
    expect(stored.cacheControl).toContain('immutable');
    const meta = await sharp(stored.body).metadata();
    expect(meta.exif).toBeUndefined();
    expect([meta.width, meta.height]).toEqual([768, 1024]);

    // The owner's other devices pull the new photoUrl; cards were republished.
    const ownerDelta = await pull(owner, ownerCursor);
    expect(ownerDelta.body.changes.profile.photoUrl).toBe(res.body.photoUrl);
    const after = await prisma.card.findUniqueOrThrow({ where: { id: c.id } });
    expect(after.contentUpdatedAt.getTime()).toBeGreaterThan(before.contentUpdatedAt.getTime());

    // People who hold this user as a connection get the new avatarUrl in their pull.
    const holderDelta = await pull(holder, holderCursor);
    expectSchema('SyncPullResponse', holderDelta.body);
    const updated = holderDelta.body.changes.connections.find((x: { id: string }) => x.id === held.id);
    expect(updated.avatarUrl).toBe(res.body.photoUrl);

    // A retried commit answers with the same profile.
    const retry = await request(server()).put('/v1/me/profile/photo').set(owner.auth).send({ uploadId }).expect(200);
    expect(retry.body.photoUrl).toBe(res.body.photoUrl);

    // A new photo replaces the old object.
    const second = await upload(owner, await jpegWithExif(400, 300));
    const replaced = await request(server()).put('/v1/me/profile/photo').set(owner.auth).send({ uploadId: second.uploadId }).expect(200);
    expect(replaced.body.photoUrl).not.toBe(res.body.photoUrl);
    expect(storage.objects.has(publicKey)).toBe(false);
    expect(storage.objects.has(storage.keyFromPublicUrl(replaced.body.photoUrl)!)).toBe(true);

    // Delete clears photoUrl and every held avatar, and removes the object.
    const cursor2 = (await pull(holder)).body.cursor;
    const cleared = await request(server()).delete('/v1/me/profile/photo').set(owner.auth).expect(200);
    expectSchema('Profile', cleared.body);
    expect(cleared.body.photoUrl).toBeUndefined();
    expect(storage.objects.has(storage.keyFromPublicUrl(replaced.body.photoUrl)!)).toBe(false);
    const holderAfter = await pull(holder, cursor2);
    const gone = holderAfter.body.changes.connections.find((x: { id: string }) => x.id === held.id);
    expect(gone.avatarUrl).toBeUndefined();
  });

  it('keeps logo transparency as WebP', async () => {
    const s = await withProfile();
    const png = await sharp({ create: { width: 320, height: 100, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
    const { uploadId } = await upload(s, png, 'logo', 'image/png');
    const res = await request(server()).put('/v1/me/profile/logo').set(s.auth).send({ uploadId }).expect(200);
    expect(res.body.logoUrl).toMatch(/\/logo-[\w-]+\.webp$/);
    expect(res.body.photoUrl).toBeUndefined();
  });

  it('refuses bad commits', async () => {
    const s = await withProfile();
    // Not uploaded yet.
    const ticket = await request(server()).post('/v1/me/profile/photo/upload').set(s.auth).send({ contentType: 'image/jpeg', byteSize: 100 }).expect(200);
    const missing = await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: ticket.body.uploadId }).expect(400);
    expect(missing.body.code).toBe('invalid_request');
    // Someone else's upload, wrong kind, unknown id.
    const other = await withProfile();
    await request(server()).put('/v1/me/profile/photo').set(other.auth).send({ uploadId: ticket.body.uploadId }).expect(404);
    await request(server()).put('/v1/me/profile/logo').set(s.auth).send({ uploadId: ticket.body.uploadId }).expect(404);
    await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: randomUUID() }).expect(404);
    await request(server()).put('/v1/me/profile/photo').set(s.auth).send({}).expect(422);

    // Not an image / HEIC that cannot be decoded.
    const junk = await upload(s, Buffer.from('definitely not an image'));
    const bad = await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: junk.uploadId }).expect(415);
    expect(bad.body.code).toBe('unsupported_media_type');
    expect(storage.objects.has(junk.key)).toBe(false);
    const heic = await upload(s, Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypheic'), Buffer.alloc(256)]), 'photo', 'image/heic');
    const heicRes = await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: heic.uploadId }).expect(415);
    expect(heicRes.body.message).toMatch(/HEIC/);

    // Larger than allowed (a store that did not enforce the signed length).
    const big = await upload(s, Buffer.alloc(100));
    await storage.putObject(big.key, Buffer.alloc(5_000_001), { contentType: 'image/jpeg' });
    const tooBig = await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: big.uploadId }).expect(413);
    expect(tooBig.body.code).toBe('payload_too_large');

    // Expired ticket.
    const late = await upload(s, await jpegWithExif(10, 10));
    await prisma.upload.update({ where: { id: late.uploadId }, data: { expiresAt: new Date(Date.now() - 3_600_000) } });
    await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId: late.uploadId }).expect(410);

    // No profile.
    const fresh = await signIn(app);
    await request(server()).put('/v1/me/profile/photo').set(fresh.auth).send({ uploadId: randomUUID() }).expect(404);
    await request(server()).delete('/v1/me/profile/photo').set(fresh.auth).expect(404);
  });

  it('builds and emails the data export', async () => {
    const s = await withProfile();
    const e = event();
    await request(server()).put(`/v1/events/${e.id}`).set(s.auth).send(e).expect(200);
    const c = card();
    await request(server()).put(`/v1/cards/${c.id}`).set(s.auth).send(c).expect(200);
    const conn = connection({ note: 'Wants a demo, "Q4"', tags: ['investor'], eventId: e.id, context: { metAt: new Date().toISOString(), eventName: 'ICT Week', city: 'Tashkent' } });
    await request(server()).put(`/v1/connections/${conn.id}`).set(s.auth).send(conn).expect(200);
    const f = followUp({ connectionId: conn.id });
    await request(server()).put(`/v1/followups/${f.id}`).set(s.auth).send(f).expect(200);
    const { uploadId } = await upload(s, await jpegWithExif(200, 200));
    await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId }).expect(200);

    const queued = await request(server()).post('/v1/me/export').set(s.auth).expect(202);
    expectSchema('DataExportResponse', queued.body);

    // A failing mail provider leaves the request queued.
    const failing = vi.fn(async () => new Response('{"message":"nope"}', { status: 500 }));
    vi.stubGlobal('fetch', failing);
    await app.get(ExportService).runOnce();
    expect((await prisma.dataExportRequest.findFirstOrThrow({ where: { userId: s.userId } })).completedAt).toBeNull();

    const sent: { url: string; init: RequestInit }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init: RequestInit) => {
        sent.push({ url, init });
        return new Response('{"id":"email_1"}', { status: 200 });
      }),
    );
    await app.get(ExportService).runOnce();
    const request_ = await prisma.dataExportRequest.findFirstOrThrow({ where: { userId: s.userId } });
    expect(request_.completedAt).not.toBeNull();

    const user = await prisma.user.findUniqueOrThrow({ where: { id: s.userId } });
    const mail = sent.find((m) => JSON.parse(String(m.init.body)).to[0] === user.email)!;
    expect(mail.url).toBe('https://api.resend.com/emails');
    expect((mail.init.headers as Record<string, string>).Authorization).toBe('Bearer re_test_key');
    const payload = JSON.parse(String(mail.init.body));
    expect(payload.to).toEqual([user.email]);
    expect(payload.from).toBe('Metly <no-reply@metly.link>');
    const link = /https:\/\/storage\.metly\.test\/\S+/.exec(payload.text)![0];
    const key = storage.keyFromPresignedUrl(link);
    expect(key).toMatch(new RegExp(`^exports/${s.userId}/[\\w-]+\\.zip$`));
    expect(link).toContain('X-Amz-Expires=604800');

    const files = await unzip(storage.objects.get(key)!.body);
    expect([...files.keys()].sort()).toEqual(
      ['cards.json', 'connections.csv', 'connections.json', 'events.json', 'followups.json', 'images/photo.jpg', 'profile.json'].sort(),
    );
    const exportedProfile = JSON.parse(files.get('profile.json')!.toString('utf8'));
    expectSchema('Profile', exportedProfile);
    // The owner's own export includes private fields.
    expect(exportedProfile.contactFields.find((f: { kind: string }) => f.kind === 'telegram').value).toBe('@kamola');
    const cards = JSON.parse(files.get('cards.json')!.toString('utf8'));
    expect(cards.map((x: { id: string }) => x.id)).toEqual([c.id]);
    const connections = JSON.parse(files.get('connections.json')!.toString('utf8'));
    expect(connections[0].note).toBe('Wants a demo, "Q4"');
    expect(JSON.parse(files.get('followups.json')!.toString('utf8'))[0].id).toBe(f.id);
    expect(JSON.parse(files.get('events.json')!.toString('utf8'))[0].id).toBe(e.id);
    const csv = files.get('connections.csv')!.toString('utf8').replace(/^﻿/, '').split('\r\n');
    expect(csv[0]).toBe('name,title,company,phone,email,telegram,website,linkedin,met at,event,place,city,tags,note');
    expect(csv[1]).toContain('Sardor Rashidov,CTO,Acme,+998907654321');
    expect(csv[1]).toContain('ICT Week');
    expect(csv[1]).toContain('"Wants a demo, ""Q4"""');
    expect((await sharp(files.get('images/photo.jpg')!).metadata()).format).toBe('jpeg');

    // Done requests are not processed again.
    const count = sent.length;
    await app.get(ExportService).runOnce();
    expect(sent.filter((m) => JSON.parse(String(m.init.body)).to[0] === user.email)).toHaveLength(1);
    expect(sent.length).toBeGreaterThanOrEqual(count);
  });

  it('deletes stored objects when the account is deleted', async () => {
    const s = await withProfile();
    const { uploadId } = await upload(s, await jpegWithExif(100, 100));
    await request(server()).put('/v1/me/profile/photo').set(s.auth).send({ uploadId }).expect(200);
    await upload(s, Buffer.from('pending raw upload'));
    await storage.putObject(`exports/${s.userId}/old.zip`, Buffer.from('zip'), { contentType: 'application/zip' });
    const mine = () => [...storage.objects.keys()].filter((k) => k.includes(`/${s.userId}/`));
    expect(mine().length).toBe(3);

    await request(server()).delete('/v1/me').set(s.auth).expect(204);
    expect(mine()).toEqual([]);
  });
});
