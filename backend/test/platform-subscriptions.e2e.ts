import { randomBytes, randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { EntitlementsJob } from '../src/platform/jobs/entitlements.job';
import { PrismaService } from '../src/prisma/prisma.service';
import { expectSchema } from './contract';
import { card, createApp, profile, request, resetRateLimits, type Session, signIn } from './helpers';

/**
 * StoreKit "Xcode" environment data: locally signed by Xcode, so the Apple library skips the
 * signature check — accepted only when NODE_ENV is not production (here: test). Real Apple-signed
 * data goes through the full x5c chain check against the vendored roots.
 */
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jws = (payload: Record<string, unknown>) => `${b64({ alg: 'ES256', typ: 'JWT' })}.${b64(payload)}.${randomBytes(64).toString('base64url')}`;
const DAY = 86_400_000;

function transaction(overrides: Record<string, unknown> = {}) {
  const t = Date.now();
  const originalTransactionId = (overrides.originalTransactionId as string) ?? String(2_000_000_000 + Math.floor(Math.random() * 1e9));
  return {
    transactionId: String(3_000_000_000 + Math.floor(Math.random() * 1e9)),
    originalTransactionId,
    bundleId: 'app.nameshake.ios',
    productId: 'app.nameshake.ios.pro.yearly',
    subscriptionGroupIdentifier: '21500001',
    purchaseDate: t - DAY,
    originalPurchaseDate: t - DAY,
    expiresDate: t + 365 * DAY,
    quantity: 1,
    type: 'Auto-Renewable Subscription',
    inAppOwnershipType: 'PURCHASED',
    signedDate: t,
    environment: 'Xcode',
    ...overrides,
  };
}

function renewal(tx: Record<string, unknown>, overrides: Record<string, unknown> = {}) {
  return {
    originalTransactionId: tx.originalTransactionId,
    autoRenewProductId: tx.productId,
    productId: tx.productId,
    autoRenewStatus: 1,
    signedDate: Date.now(),
    environment: 'Xcode',
    renewalDate: tx.expiresDate,
    recentSubscriptionStartDate: tx.purchaseDate,
    ...overrides,
  };
}

function notification(type: string, tx: Record<string, unknown>, opts: { renewal?: Record<string, unknown>; subtype?: string; uuid?: string; status?: number } = {}) {
  return {
    signedPayload: jws({
      notificationType: type,
      ...(opts.subtype ? { subtype: opts.subtype } : {}),
      notificationUUID: opts.uuid ?? randomUUID(),
      data: {
        environment: 'Xcode',
        bundleId: 'app.nameshake.ios',
        bundleVersion: '42',
        signedTransactionInfo: jws(tx),
        signedRenewalInfo: jws(opts.renewal ?? renewal(tx)),
        ...(opts.status ? { status: opts.status } : {}),
      },
      version: '2.0',
      signedDate: Date.now(),
    }),
  };
}

describe('platform: App Store subscriptions', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(() => app.close());
  beforeEach(() => resetRateLimits(app));

  const http = () => request(app.getHttpServer());
  const verify = (s: Session, tx: Record<string, unknown>) =>
    http().post('/v1/subscriptions/verify').set(s.auth).set('Idempotency-Key', randomUUID()).send({ signedTransaction: jws(tx), appAccountToken: s.userId });
  const webhook = (body: object) => http().post('/v1/webhooks/app-store').send(body);
  const pull = (s: Session, since?: string) =>
    http()
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(s.auth)
      .expect(200);

  it('verifies a StoreKit transaction into a Pro entitlement with the app’s product id', async () => {
    const s = await signIn(app);
    const tx = transaction();
    const res = await verify(s, tx).expect(200);
    expectSchema('Entitlement', res.body);
    expect(res.body).toMatchObject({
      plan: 'pro',
      productId: 'app.nameshake.ios.pro.yearly',
      originalTransactionId: tx.originalTransactionId,
      environment: 'Xcode',
      willRenew: true,
      isInBillingRetry: false,
      limits: { maxCards: null, maxOpenFollowUps: null, maxActiveEvents: null },
    });
    const current = await http().get('/v1/me/entitlements').set(s.auth).expect(200);
    expectSchema('Entitlement', current.body);
    expect(current.body.plan).toBe('pro');
    expect((await pull(s)).body.entitlement.plan).toBe('pro');
  });

  it('never lets one transaction unlock two accounts', async () => {
    const a = await signIn(app);
    const b = await signIn(app);
    const tx = transaction();
    await verify(a, tx).expect(200);
    const res = await verify(b, { ...tx, transactionId: String(Date.now()) }).expect(409);
    expectSchema('Error', res.body);
    expect(res.body.code).toBe('conflict');
    // Bought for another (existing) account via appAccountToken.
    const c = await signIn(app);
    await verify(c, transaction({ appAccountToken: a.userId })).expect(409);
  });

  it('rejects other products, unaccepted environments and unconfigured verification', async () => {
    const s = await signIn(app);
    expect((await verify(s, transaction({ productId: 'com.example.other.yearly' })).expect(400)).body.code).toBe('invalid_request');
    // APP_STORE_ENVIRONMENT defaults to Sandbox: Production data is not accepted.
    await verify(s, transaction({ environment: 'Production' })).expect(400);
    // Sandbox purchases need the App Store Server API credentials (not set in tests).
    expect((await verify(s, transaction({ environment: 'Sandbox' })).expect(503)).body.code).toBe('service_unavailable');
    await http().post('/v1/subscriptions/verify').set(s.auth).send({ signedTransaction: 'garbage' }).expect(400);
    await http().post('/v1/subscriptions/verify').set(s.auth).send({}).expect(422);
  });

  it('keeps a longer active subscription when an older transaction is verified', async () => {
    const s = await signIn(app);
    const long = transaction({ expiresDate: Date.now() + 300 * DAY });
    await verify(s, long).expect(200);
    const short = transaction({ productId: 'app.nameshake.ios.pro.monthly', expiresDate: Date.now() + 20 * DAY });
    const res = await verify(s, short).expect(200);
    expect(res.body).toMatchObject({ productId: 'app.nameshake.ios.pro.yearly', originalTransactionId: long.originalTransactionId });
    const expired = transaction({ expiresDate: Date.now() - DAY, purchaseDate: Date.now() - 40 * DAY });
    expect((await verify(s, expired).expect(200)).body.originalTransactionId).toBe(long.originalTransactionId);
  });

  it('downgrade makes cards beyond the 2 lowest sortOrder read-only; renewal clears it; webhooks are idempotent', async () => {
    const s = await signIn(app);
    const tx = transaction();
    await verify(s, tx).expect(200);
    const cards = [3, 0, 2, 1].map((sortOrder) => card({ name: `Card ${sortOrder}`, sortOrder }));
    await http().post('/v1/sync/push').set(s.auth).send({ changes: { profile: profile(), cards } }).expect(200);
    const cursor = (await pull(s)).body.cursor as string;

    // EXPIRED carries the subscription's last transaction (the expiry already stored).
    const expiredTx = { ...tx, signedDate: Date.now() };
    const expiredUuid = randomUUID();
    await webhook(notification('EXPIRED', expiredTx, { subtype: 'VOLUNTARY', uuid: expiredUuid, renewal: renewal(expiredTx, { autoRenewStatus: 0 }) })).expect(200);

    const delta = await pull(s, cursor);
    expectSchema('SyncPullResponse', delta.body);
    expect(delta.body.entitlement).toMatchObject({ plan: 'free', willRenew: false, limits: { maxCards: 2 } });
    const readOnly = Object.fromEntries((delta.body.changes.cards as { name: string; isReadOnly: boolean }[]).map((c) => [c.name, c.isReadOnly]));
    expect(readOnly).toEqual({ 'Card 2': true, 'Card 3': true });
    const stored = await prisma.card.findMany({ where: { userId: s.userId }, orderBy: { sortOrder: 'asc' } });
    expect(stored.map((c) => c.isReadOnly)).toEqual([false, false, true, true]);
    // Read-only cards stay published but refuse content edits on Free.
    const locked = stored[3]!;
    await http()
      .put(`/v1/cards/${locked.id}`)
      .set(s.auth)
      .send({ ...cards.find((c) => c.id === locked.id), name: 'Renamed', updatedAt: new Date(Date.now() + 5000).toISOString() })
      .expect(403);

    // Resubscribed: same subscription (originalTransactionId), a later period.
    const renewedTx = { ...tx, transactionId: String(Date.now()), purchaseDate: Date.now(), expiresDate: tx.expiresDate + 30 * DAY };
    await webhook(notification('DID_RENEW', renewedTx)).expect(200);
    expect((await prisma.card.findMany({ where: { userId: s.userId } })).every((c) => !c.isReadOnly)).toBe(true);
    expect((await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body.plan).toBe('pro');

    // Apple redelivers the old EXPIRED notification: stored already, nothing changes.
    await webhook(notification('EXPIRED', expiredTx, { uuid: expiredUuid })).expect(200);
    expect((await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body.plan).toBe('pro');
    expect(await prisma.appStoreNotification.count({ where: { notificationUUID: expiredUuid } })).toBe(1);
  });

  it('billing retry keeps Pro; refund and revoke end it; renewal-status changes update willRenew', async () => {
    const s = await signIn(app);
    const tx = transaction({ expiresDate: Date.now() + 10 * DAY });
    await verify(s, tx).expect(200);

    await webhook(notification('DID_CHANGE_RENEWAL_STATUS', tx, { subtype: 'AUTO_RENEW_DISABLED', renewal: renewal(tx, { autoRenewStatus: 0 }) })).expect(200);
    let e = (await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body;
    expect(e).toMatchObject({ plan: 'pro', willRenew: false });

    // Renewal failed at the stored expiry: the notification carries that last transaction.
    const lapsed = { ...tx, signedDate: Date.now() };
    await webhook(notification('DID_FAIL_TO_RENEW', lapsed, { renewal: renewal(lapsed, { isInBillingRetryPeriod: true }) })).expect(200);
    e = (await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body;
    expect(e).toMatchObject({ plan: 'pro', isInBillingRetry: true });

    await webhook(notification('REFUND', { ...lapsed, revocationDate: Date.now(), revocationReason: 0 })).expect(200);
    e = (await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body;
    expect(e).toMatchObject({ plan: 'free', isInBillingRetry: false, willRenew: false });
  });

  it('links a notification to the buyer through appAccountToken and records unknown purchases', async () => {
    const s = await signIn(app);
    const tx = transaction({ appAccountToken: s.userId });
    await webhook(notification('SUBSCRIBED', tx, { subtype: 'INITIAL_BUY' })).expect(200);
    expect((await http().get('/v1/me/entitlements').set(s.auth).expect(200)).body).toMatchObject({
      plan: 'pro',
      originalTransactionId: tx.originalTransactionId,
    });

    const orphanUuid = randomUUID();
    await webhook(notification('SUBSCRIBED', transaction(), { uuid: orphanUuid })).expect(200);
    expect(await prisma.appStoreNotification.findUnique({ where: { notificationUUID: orphanUuid } })).not.toBeNull();
    await webhook({ signedPayload: 'not-a-jws' }).expect(400);
  });

  it('turns lapsed Pro into Free when no EXPIRED notification arrives', async () => {
    const s = await signIn(app);
    await verify(s, transaction()).expect(200);
    const cards = [0, 1, 2].map((sortOrder) => card({ sortOrder }));
    await http().post('/v1/sync/push').set(s.auth).send({ changes: { cards } }).expect(200);
    await prisma.entitlement.update({ where: { userId: s.userId }, data: { expiresAt: new Date(Date.now() - 60_000) } });
    const result = await app.get(EntitlementsJob).runOnce();
    expect(result?.expired).toBeGreaterThanOrEqual(1);
    const e = await prisma.entitlement.findUniqueOrThrow({ where: { userId: s.userId } });
    expect(e.plan).toBe('free');
    const stored = await prisma.card.findMany({ where: { userId: s.userId }, orderBy: { sortOrder: 'asc' } });
    expect(stored.map((c) => c.isReadOnly)).toEqual([false, false, true]);
  });
});
