import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { TestPassPushSink } from '../src/media/wallet/pass-push';
import { PassUpdatesService } from '../src/media/wallet/pass-updates.service';
import { PrismaService } from '../src/prisma/prisma.service';
import { card, createApp, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';
import { unzip } from './media-helpers';

/** A throwaway self-signed "Pass Type ID" certificate (also used as the WWDR stand-in). */
function testCertificate(): { cert: string; key: string } | null {
  const dir = mkdtempSync(join(tmpdir(), 'metly-pass-'));
  try {
    execFileSync(
      'openssl',
      ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(dir, 'key.pem'), '-out', join(dir, 'cert.pem'), '-days', '2', '-subj', '/CN=Pass Type ID: pass.app.tanishly.ios.card/OU=TEAM123456'],
      { stdio: 'pipe' },
    );
    return { cert: readFileSync(join(dir, 'cert.pem'), 'utf8'), key: readFileSync(join(dir, 'key.pem'), 'utf8') };
  } catch {
    return null;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const certificate = testCertificate();
const PASS_TYPE = 'pass.app.tanishly.ios.card';
const PUSH_TOKEN = 'a'.repeat(64);

async function until(check: () => boolean, timeoutMs = 3000, refresh?: () => Promise<void>) {
  const start = Date.now();
  await refresh?.();
  while (!check()) {
    if (Date.now() - start > timeoutMs) throw new Error('condition not met in time');
    await new Promise((r) => setTimeout(r, 20));
    await refresh?.();
  }
}

describe.skipIf(!certificate)('Apple Wallet', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    process.env.PASS_TEAM_ID = 'TEAM123456';
    process.env.PASS_CERT_PEM = certificate!.cert;
    process.env.PASS_KEY_PEM = certificate!.key;
    process.env.PASS_WWDR_PEM = certificate!.cert;
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(async () => {
    await app.close();
    for (const key of ['PASS_TEAM_ID', 'PASS_CERT_PEM', 'PASS_KEY_PEM', 'PASS_WWDR_PEM']) delete process.env[key];
  });
  beforeEach(async () => {
    await resetRateLimits(app);
    TestPassPushSink.clear();
  });

  const server = () => app.getHttpServer();
  /** supertest parser that keeps a binary body as a Buffer. */
  const binary = (res: unknown, callback: (error: Error | null, body: unknown) => void) => {
    const stream = res as NodeJS.ReadableStream;
    const chunks: Buffer[] = [];
    stream.on('data', (c: Buffer) => chunks.push(c));
    stream.on('end', () => callback(null, Buffer.concat(chunks)));
  };

  const setup = async (): Promise<{ s: Session; cardId: string; token: string; c: ReturnType<typeof card> }> => {
    const s = await signIn(app);
    await request(server()).put('/v1/me/profile').set(s.auth).send(profile()).expect(200);
    const c = card({ design: { ...card().design, palette: 'ink', appearance: 'dark', visibleFields: ['phone', 'email', 'telegram'] } });
    await request(server()).put(`/v1/cards/${c.id}`).set(s.auth).send(c).expect(200);
    const stored = await prisma.card.findUniqueOrThrow({ where: { id: c.id } });
    return { s, cardId: c.id, token: stored.passAuthToken, c };
  };

  it('signs a pass with public fields only', async () => {
    const { s, cardId, token } = await setup();
    const res = await request(server()).get(`/v1/cards/${cardId}/wallet-pass`).set(s.auth).buffer(true).parse(binary).expect(200);
    expect(res.headers['content-type']).toBe('application/vnd.apple.pkpass');
    expect(res.headers['last-modified']).toBeTruthy();
    const files = await unzip(res.body as Buffer);
    for (const name of ['pass.json', 'manifest.json', 'signature', 'icon.png', 'icon@2x.png', 'icon@3x.png', 'logo.png', 'logo@2x.png']) {
      expect(files.has(name), name).toBe(true);
    }
    const pass = JSON.parse(files.get('pass.json')!.toString('utf8'));
    const stored = await prisma.card.findUniqueOrThrow({ where: { id: cardId } });
    expect(pass).toMatchObject({
      passTypeIdentifier: PASS_TYPE,
      teamIdentifier: 'TEAM123456',
      serialNumber: cardId,
      authenticationToken: token,
      webServiceURL: 'https://api.metly.test/passkit',
      organizationName: 'Nameshake',
      backgroundColor: 'rgb(8, 17, 31)',
    });
    expect(pass.barcodes[0]).toMatchObject({ format: 'PKBarcodeFormatQR', message: `https://metly.test/c/${stored.slug}`, messageEncoding: 'iso-8859-1' });
    const text = files.get('pass.json')!.toString('utf8');
    expect(text).toContain('+998901234567');
    expect(text).not.toContain('kamola@metly.test'); // connections-level
    expect(text).not.toContain('@kamola'); // private
    const manifest = JSON.parse(files.get('manifest.json')!.toString('utf8'));
    expect(Object.keys(manifest)).toContain('pass.json');
  });

  it('serves passes to the owner of a live card only', async () => {
    const { cardId } = await setup();
    const stranger = await signIn(app);
    await request(server()).get(`/v1/cards/${cardId}/wallet-pass`).set(stranger.auth).expect(404);
    await request(server()).get('/v1/cards/not-a-uuid/wallet-pass').set(stranger.auth).expect(422);
  });

  it('implements the PassKit web service', async () => {
    const { s, cardId, token, c } = await setup();
    const base = `/passkit/v1/devices/device-lib-1/registrations/${PASS_TYPE}`;
    const auth = { Authorization: `ApplePass ${token}` };

    // Auth and pass type checks.
    await request(server()).post(`${base}/${cardId}`).send({ pushToken: PUSH_TOKEN }).expect(401);
    await request(server()).post(`${base}/${cardId}`).set({ Authorization: 'ApplePass wrong-token-wrong-token' }).send({ pushToken: PUSH_TOKEN }).expect(401);
    await request(server()).post(`/passkit/v1/devices/device-lib-1/registrations/pass.other/${cardId}`).set(auth).send({ pushToken: PUSH_TOKEN }).expect(404);
    await request(server()).post(`${base}/${cardId}`).set(auth).send({ pushToken: 'nope' }).expect(422);

    // Register: 201 new, 200 existing.
    await request(server()).post(`${base}/${cardId}`).set(auth).send({ pushToken: PUSH_TOKEN }).expect(201);
    await request(server()).post(`${base}/${cardId}`).set(auth).send({ pushToken: PUSH_TOKEN }).expect(200);

    // Updated serials.
    const all = await request(server()).get(base).expect(200);
    expect(all.body.serialNumbers).toEqual([cardId]);
    const tag = all.body.lastUpdated as string;
    expect(tag).toMatch(/^\d+$/);
    await request(server()).get(base).query({ passesUpdatedSince: tag }).expect(204);
    await request(server()).get(`/passkit/v1/devices/unknown-device/registrations/${PASS_TYPE}`).expect(204);
    await request(server()).get('/passkit/v1/devices/device-lib-1/registrations/pass.other').expect(404);

    // Latest pass + If-Modified-Since.
    await request(server()).get(`/passkit/v1/passes/${PASS_TYPE}/${cardId}`).expect(401);
    const latest = await request(server()).get(`/passkit/v1/passes/${PASS_TYPE}/${cardId}`).set(auth).buffer(true).parse(binary).expect(200);
    expect(latest.headers['content-type']).toBe('application/vnd.apple.pkpass');
    const lastModified = latest.headers['last-modified'] as string;
    await request(server()).get(`/passkit/v1/passes/${PASS_TYPE}/${cardId}`).set(auth).set('If-Modified-Since', lastModified).expect(304);

    // A public change pushes the device, and the pass shows up as updated.
    await new Promise((r) => setTimeout(r, 5));
    await request(server()).put(`/v1/cards/${cardId}`).set(s.auth).send({ ...c, name: 'Personal', updatedAt: now(1000) }).expect(200);
    await until(() => TestPassPushSink.sent.length > 0);
    expect(TestPassPushSink.sent[0]).toEqual({ pushToken: PUSH_TOKEN, topic: PASS_TYPE, payload: '{}' });
    const changed = await request(server()).get(base).query({ passesUpdatedSince: tag }).expect(200);
    expect(changed.body.serialNumbers).toEqual([cardId]);
    expect(Number(changed.body.lastUpdated)).toBeGreaterThan(Number(tag));

    // Log endpoint.
    await request(server()).post('/passkit/v1/log').send({ logs: ['Web service error for pass.app.tanishly.ios.card'] }).expect(200);

    // Unregister.
    await request(server()).delete(`${base}/${cardId}`).expect(401);
    await request(server()).delete(`${base}/${cardId}`).set(auth).expect(200);
    await request(server()).get(base).expect(204);
  });

  it('forgets registrations APNs reports as unregistered and voids deleted cards', async () => {
    const { s, cardId, token } = await setup();
    const auth = { Authorization: `ApplePass ${token}` };
    const deadToken = 'b'.repeat(64);
    await request(server()).post(`/passkit/v1/devices/device-lib-2/registrations/${PASS_TYPE}/${cardId}`).set(auth).send({ pushToken: deadToken }).expect(201);
    TestPassPushSink.unregistered.add(deadToken);
    expect(await app.get(PassUpdatesService).cardsChanged([cardId])).toBe(0);
    expect(TestPassPushSink.sent.map((p) => p.pushToken)).toEqual([deadToken]);
    expect(await prisma.passRegistration.count({ where: { pushToken: deadToken } })).toBe(0);

    // Deleting the card: the latest pass is voided (Wallet shows it as no longer valid).
    const before = (await prisma.card.findUniqueOrThrow({ where: { id: cardId } })).contentUpdatedAt;
    await request(server()).delete(`/v1/cards/${cardId}`).set(s.auth).expect(204);
    // The tombstone moves the update tag, so Wallet fetches the voided pass.
    let after = before;
    await until(() => after > before, 3000, async () => {
      after = (await prisma.card.findUniqueOrThrow({ where: { id: cardId } })).contentUpdatedAt;
    });
    const latest = await request(server()).get(`/passkit/v1/passes/${PASS_TYPE}/${cardId}`).set(auth).buffer(true).parse(binary).expect(200);
    const pass = JSON.parse((await unzip(latest.body as Buffer)).get('pass.json')!.toString('utf8'));
    expect(pass.voided).toBe(true);
    expect(pass.barcodes).toBeUndefined();
    await request(server()).get(`/v1/cards/${cardId}/wallet-pass`).set(s.auth).expect(404);
  });
});
