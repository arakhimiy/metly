// Local PostgreSQL for development without Docker: `npm run db:start` (Ctrl-C stops it).
// Data lives in backend/.pg-data; DATABASE_URL in .env.example points here.
import EmbeddedPostgres from 'embedded-postgres';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const dataDir = fileURLToPath(new URL('../.pg-data', import.meta.url));
const port = Number(process.env.DEV_DB_PORT ?? 54329);
const pg = new EmbeddedPostgres({ databaseDir: dataDir, user: 'metly', password: 'metly', port, persistent: true });

if (!existsSync(dataDir)) await pg.initialise();
await pg.start();
for (const name of ['metly', 'metly_test']) {
  try {
    await pg.createDatabase(name);
  } catch {
    // already exists
  }
}
console.log(`PostgreSQL ready on postgresql://metly:metly@127.0.0.1:${port}/metly`);

const stop = async () => {
  await pg.stop();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
