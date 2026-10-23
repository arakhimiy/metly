import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// DATABASE_URL is only required by commands that talk to the database (migrate, studio);
// `prisma generate` runs without it, e.g. in the Docker build.
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: { path: 'prisma/migrations' },
  datasource: { url: process.env.DATABASE_URL ?? '' },
});
