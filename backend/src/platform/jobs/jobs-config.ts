/**
 * Scheduled timers are off under `NODE_ENV=test`: e2e tests drive each job through `runOnce(now)`.
 * Read from process.env because @Cron options are fixed when the class is decorated (test/setup-env.ts
 * sets NODE_ENV before any app module is imported).
 */
export const JOBS_DISABLED = process.env.NODE_ENV === 'test';
