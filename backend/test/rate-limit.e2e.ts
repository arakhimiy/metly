import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { type Budget, PostgresRateLimitStore, RateLimitStore } from '../src/common/rate-limit';
import { PrismaService } from '../src/prisma/prisma.service';
import { createApp, request, resetRateLimits } from './helpers';

const budget: Budget = { limit: 5, windowSeconds: 60, by: 'ip' };

describe('rate limits (shared Postgres store)', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  it('is the store the app uses by default', () => {
    expect(app.get(RateLimitStore)).toBeInstanceOf(PostgresRateLimitStore);
  });

  it('counts concurrent hits from several instances against one budget', async () => {
    // Two stores = two API instances sharing the database.
    const a = new PostgresRateLimitStore(prisma);
    const b = new PostgresRateLimitStore(prisma);
    const results = await Promise.all(Array.from({ length: 8 }, (_, i) => (i % 2 ? a : b).hit('shared', budget)));
    expect(results.filter((r) => r.allowed)).toHaveLength(5);
    expect(new Set(results.map((r) => r.resetAt)).size).toBe(1);
  });

  it('starts a fresh window once the previous one ended', async () => {
    const store = new PostgresRateLimitStore(prisma);
    const t0 = Date.now();
    for (let i = 0; i < 5; i++) await store.hit('rolling', budget, t0);
    expect((await store.hit('rolling', budget, t0)).allowed).toBe(false);
    const later = await store.hit('rolling', budget, t0 + 60_001);
    expect(later).toMatchObject({ allowed: true, remaining: 4 });
    expect(later.resetAt).toBe(t0 + 60_001 + 60_000);
  });

  it('limits auth by client IP from X-Forwarded-For (one trusted hop) and answers 429 with Retry-After', async () => {
    const send = (ip: string) =>
      request(app.getHttpServer()).post('/v1/auth/refresh').set('X-Forwarded-For', ip).send({ refreshToken: 'nope' });
    for (let i = 0; i < 10; i++) expect((await send('198.51.100.7')).status).not.toBe(429);
    const limited = await send('198.51.100.7');
    expect(limited.status).toBe(429);
    expect(Number(limited.headers['retry-after'])).toBeGreaterThan(0);
    // Another client is unaffected.
    expect((await send('198.51.100.8')).status).not.toBe(429);
  });

  it('ignores spoofed addresses to the left of the trusted proxy', async () => {
    const send = (spoofed: string) =>
      request(app.getHttpServer())
        .post('/v1/auth/refresh')
        .set('X-Forwarded-For', `${spoofed}, 198.51.100.20`)
        .send({ refreshToken: 'nope' });
    for (let i = 0; i < 10; i++) await send(`192.0.2.${i}`);
    expect((await send('192.0.2.99')).status).toBe(429);
  });
});
