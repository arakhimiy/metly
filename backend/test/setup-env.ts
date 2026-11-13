import { inject } from 'vitest';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = inject('databaseUrl');
process.env.WEB_BASE_URL = 'https://metly.test';
process.env.API_BASE_URL = 'https://api.metly.test';
process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-test-secret';
process.env.DEV_AUTH_ENABLED = 'true';
process.env.APPLE_BUNDLE_IDS = 'app.nameshake.ios';
process.env.LOG_LEVEL = 'silent';
