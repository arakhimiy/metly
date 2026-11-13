import { describe, expect, it } from 'vitest';
import { type Budget, MemoryRateLimitStore } from './rate-limit';

const budget: Budget = { limit: 3, windowSeconds: 60, by: 'ip' };

describe('MemoryRateLimitStore', () => {
  it('allows up to the limit, then refuses until the window ends', async () => {
    const store = new MemoryRateLimitStore();
    const t0 = 1_000_000;
    const results = [];
    for (let i = 0; i < 4; i++) results.push(await store.hit('k', budget, t0 + i));
    expect(results.map((r) => r.allowed)).toEqual([true, true, true, false]);
    expect(results.map((r) => r.remaining)).toEqual([2, 1, 0, 0]);
    expect(results[3]?.resetAt).toBe(t0 + 60_000);

    const next = await store.hit('k', budget, t0 + 60_000);
    expect(next).toEqual({ allowed: true, remaining: 2, resetAt: t0 + 120_000 });
  });

  it('keeps keys apart and forgets everything on reset', async () => {
    const store = new MemoryRateLimitStore();
    for (let i = 0; i < 3; i++) await store.hit('a', budget);
    expect(await store.check('a', budget)).toBe(false);
    expect(await store.check('b', budget)).toBe(true);
    await store.reset();
    expect(await store.check('a', budget)).toBe(true);
  });
});
