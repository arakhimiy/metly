import { randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PrismaService } from '../src/prisma/prisma.service';
import { expectSchema } from './contract';
import { createApp, request, resetRateLimits, signIn } from './helpers';

describe('auth', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  it('creates the account on first sign-in and finds it again afterwards', async () => {
    const subject = randomUUID();
    const first = await request(app.getHttpServer()).post('/v1/auth/dev').send({ subject, fullName: 'Kamola' }).expect(200);
    expectSchema('AuthResponse', first.body);
    expect(first.body.isNewUser).toBe(true);
    expect(first.body.suggestedName).toBe('Kamola');
    expect(first.body.user.profileComplete).toBe(false);

    const again = await request(app.getHttpServer()).post('/v1/auth/dev').send({ subject }).expect(200);
    expect(again.body.isNewUser).toBe(false);
    expect(again.body.user.id).toBe(first.body.user.id);
  });

  it('answers GET /v1/me with the user and a free entitlement', async () => {
    const session = await signIn(app);
    const res = await request(app.getHttpServer()).get('/v1/me').set(session.auth).expect(200);
    expectSchema('MeResponse', res.body);
    expect(res.body.entitlement.plan).toBe('free');
    expect(res.body.entitlement.limits).toEqual({ maxCards: 2, maxOpenFollowUps: 5, maxActiveEvents: 1 });
  });

  it('rejects missing and bad tokens with the Error body', async () => {
    const missing = await request(app.getHttpServer()).get('/v1/me').expect(401);
    expectSchema('Error', missing.body);
    expect(missing.body.code).toBe('unauthorized');
    await request(app.getHttpServer()).get('/v1/me').set('Authorization', 'Bearer nope').expect(401);
  });

  it('rotates refresh tokens and returns the same pair for a retry inside the grace window', async () => {
    const session = await signIn(app);
    const a = await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(200);
    expectSchema('SessionTokens', a.body);
    expect(a.body.refreshToken).not.toBe(session.refreshToken);
    const b = await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(200);
    expect(b.body).toEqual(a.body);
    // The new access token works.
    await request(app.getHttpServer()).get('/v1/me').set('Authorization', `Bearer ${a.body.accessToken}`).expect(200);
  });

  it('revokes the whole family when a rotated token is replayed after the grace window', async () => {
    const session = await signIn(app);
    const rotated = await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(200);
    await prisma.refreshToken.updateMany({ where: { userId: session.userId, rotatedAt: { not: null } }, data: { rotatedAt: new Date(Date.now() - 60_000) } });

    const replay = await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(401);
    expect(replay.body.code).toBe('invalid_grant');
    // The legitimate child is revoked too (theft detection).
    await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: rotated.body.refreshToken }).expect(401);
  });

  it('logs out by revoking the refresh token', async () => {
    const session = await signIn(app);
    await request(app.getHttpServer()).post('/v1/auth/logout').set(session.auth).send({ refreshToken: session.refreshToken, allDevices: false }).expect(204);
    await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(401);
  });

  it('rate-limits sign-in per IP', async () => {
    for (let i = 0; i < 10; i++) await request(app.getHttpServer()).post('/v1/auth/dev').send({ subject: randomUUID() }).expect(200);
    const limited = await request(app.getHttpServer()).post('/v1/auth/dev').send({ subject: randomUUID() }).expect(429);
    expect(limited.body.code).toBe('rate_limited');
    expect(Number(limited.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('deletes the account and everything in it', async () => {
    const session = await signIn(app);
    await request(app.getHttpServer()).delete('/v1/me').set(session.auth).expect(204);
    expect(await prisma.user.findUnique({ where: { id: session.userId } })).toBeNull();
    await request(app.getHttpServer()).post('/v1/auth/refresh').send({ refreshToken: session.refreshToken }).expect(401);
  });
});
