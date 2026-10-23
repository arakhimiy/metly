import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import EmbeddedPostgres from 'embedded-postgres';

// A throwaway PostgreSQL per test run, migrated with the real migrations.
export default async function setup({ provide }: { provide: (key: string, value: unknown) => void }) {
  const dir = mkdtempSync(join(tmpdir(), 'metly-pg-'));
  const port = 55000 + Math.floor(Math.random() * 900);
  const pg = new EmbeddedPostgres({ databaseDir: dir, user: 'metly', password: 'metly', port, persistent: false, onLog: () => {}, onError: () => {} });
  await pg.initialise();
  await pg.start();
  await pg.createDatabase('metly_e2e');
  const url = `postgresql://metly:metly@127.0.0.1:${port}/metly_e2e`;
  execFileSync('npx', ['prisma', 'migrate', 'deploy'], { env: { ...process.env, DATABASE_URL: url }, stdio: 'pipe' });
  provide('databaseUrl', url);
  return async () => {
    await pg.stop();
    rmSync(dir, { recursive: true, force: true });
  };
}

declare module 'vitest' {
  export interface ProvidedContext {
    databaseUrl: string;
  }
}
