import { describe, expect, it } from 'vitest';
import { loadEnv } from './env';

const base = {
  DATABASE_URL: 'postgresql://x@localhost/x',
  WEB_BASE_URL: 'http://localhost:3000',
  API_BASE_URL: 'http://localhost:3000',
  JWT_SECRET: 'a'.repeat(40),
};

describe('TRUST_PROXY', () => {
  it('defaults to one proxy hop', () => {
    expect(loadEnv(base).TRUST_PROXY).toBe(1);
  });

  it('accepts a hop count, a subnet list or false', () => {
    expect(loadEnv({ ...base, TRUST_PROXY: '2' }).TRUST_PROXY).toBe(2);
    expect(loadEnv({ ...base, TRUST_PROXY: 'false' }).TRUST_PROXY).toBe(false);
    expect(loadEnv({ ...base, TRUST_PROXY: 'loopback, 10.0.0.0/8' }).TRUST_PROXY).toEqual(['loopback', '10.0.0.0/8']);
  });

  it('refuses "true", which would trust any client-supplied X-Forwarded-For', () => {
    expect(() => loadEnv({ ...base, TRUST_PROXY: 'true' })).toThrow(/TRUST_PROXY/);
  });
});

describe('RATE_LIMIT_STORE', () => {
  it('shares counters through Postgres unless told otherwise', () => {
    expect(loadEnv(base).RATE_LIMIT_STORE).toBe('postgres');
    expect(loadEnv({ ...base, RATE_LIMIT_STORE: 'memory' }).RATE_LIMIT_STORE).toBe('memory');
  });
});
