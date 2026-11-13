import { randomUUID } from 'node:crypto';
import type { INestApplication } from '@nestjs/common';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { RateLimitStore } from '../src/common/rate-limit';
import { loadEnv } from '../src/config/env';

export async function createApp(): Promise<NestExpressApplication> {
  const env = loadEnv();
  const moduleRef = await Test.createTestingModule({ imports: [AppModule.forRoot(env)] }).compile();
  const app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false, logger: false });
  configureApp(app, env);
  await app.init();
  return app;
}

/** Rate limits would trip across a whole test file; reset between tests. */
export function resetRateLimits(app: INestApplication): Promise<void> {
  return app.get(RateLimitStore).reset();
}

export interface Session {
  userId: string;
  accessToken: string;
  refreshToken: string;
  auth: { Authorization: string };
}

export async function signIn(app: INestApplication, subject = randomUUID(), fullName = 'Kamola Yusupova'): Promise<Session> {
  const res = await request(app.getHttpServer()).post('/v1/auth/dev').send({ subject, fullName }).expect(200);
  return {
    userId: res.body.user.id,
    accessToken: res.body.session.accessToken,
    refreshToken: res.body.session.refreshToken,
    auth: { Authorization: `Bearer ${res.body.session.accessToken}` },
  };
}

export const now = (offsetMs = 0) => new Date(Date.now() + offsetMs).toISOString();

export const notificationPrefs = {
  followUpReminders: true,
  eventSummary: true,
  connectRequests: true,
  cardSaved: true,
  weeklySummary: false,
  productNews: false,
};

export function profile(overrides: Record<string, unknown> = {}) {
  const t = now();
  return {
    id: randomUUID(),
    fullName: 'Kamola Yusupova',
    jobTitle: 'Product Manager',
    company: 'Nameshake',
    contactFields: [
      { kind: 'phone', value: '+998901234567', privacy: 'public' },
      { kind: 'email', value: 'kamola@metly.test', privacy: 'connections' },
      { kind: 'telegram', value: '@kamola', privacy: 'private' },
      { kind: 'website', value: '', privacy: 'public' },
      { kind: 'linkedin', value: '', privacy: 'public' },
    ],
    linksPaused: false,
    notificationPrefs,
    privacySettings: { findByEmail: true, showInNearby: true, shareAnalytics: true },
    isSetupComplete: true,
    createdAt: t,
    updatedAt: t,
    ...overrides,
  };
}

export const design = {
  template: 'minimal',
  palette: 'graphite',
  appearance: 'light',
  font: 'system',
  alignment: 'leading',
  density: 'balanced',
  background: 'solid',
  showQR: true,
  showPhoto: false,
  showLogo: false,
  visibleFields: ['phone', 'email', 'telegram'],
};

export function card(overrides: Record<string, unknown> = {}) {
  const t = now();
  return {
    id: randomUUID(),
    name: 'Work',
    sortOrder: 0,
    design,
    publishState: 'draft',
    isReadOnly: false,
    isPaused: false,
    createdAt: t,
    updatedAt: t,
    ...overrides,
  };
}

export function connection(overrides: Record<string, unknown> = {}) {
  const t = now();
  return {
    id: randomUUID(),
    fullName: 'Sardor Rashidov',
    jobTitle: 'CTO',
    company: 'Acme',
    phone: '+998907654321',
    email: '',
    telegram: '@sardor',
    website: '',
    linkedin: '',
    source: 'scanQR',
    context: { metAt: t },
    previousMeetings: [],
    note: '',
    tags: [],
    isMerged: false,
    isPendingMerge: false,
    isBlocked: false,
    createdAt: t,
    updatedAt: t,
    ...overrides,
  };
}

export function followUp(overrides: Record<string, unknown> = {}) {
  const t = now();
  return {
    id: randomUUID(),
    title: 'Send the deck',
    channel: 'telegram',
    dueAt: now(86_400_000),
    isDone: false,
    createdAt: t,
    updatedAt: t,
    ...overrides,
  };
}

export function event(overrides: Record<string, unknown> = {}) {
  const t = now();
  return {
    id: randomUUID(),
    name: 'ICT Week',
    place: 'Expo Center',
    city: 'Tashkent',
    startDate: t,
    endDate: now(86_400_000),
    status: 'active',
    createdAt: t,
    updatedAt: t,
    ...overrides,
  };
}

export { request };
