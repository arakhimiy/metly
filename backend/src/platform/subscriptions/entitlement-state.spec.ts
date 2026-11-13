import { describe, expect, it } from 'vitest';
import type { JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import { isPro } from '../../subscriptions/entitlements.service';
import { type EntitlementData, nextEntitlement, type SubscriptionSnapshot, snapshotFrom } from './entitlement-state';
import { notificationSnapshot } from './subscriptions.service';

const NOW = new Date('2026-10-23T12:00:00Z');
const DAY = 86_400_000;
const at = (days: number) => new Date(NOW.getTime() + days * DAY);

function tx(overrides: Partial<JWSTransactionDecodedPayload> = {}): JWSTransactionDecodedPayload {
  return {
    originalTransactionId: '1000',
    transactionId: '2000',
    productId: 'app.nameshake.ios.pro.yearly',
    expiresDate: at(30).getTime(),
    environment: 'Sandbox',
    ...overrides,
  } as JWSTransactionDecodedPayload;
}

const stored = (s: SubscriptionSnapshot): EntitlementData => nextEntitlement(null, s, NOW)!;

describe('entitlement state', () => {
  it('snapshots an active transaction as renewing Pro', () => {
    const s = snapshotFrom(tx(), undefined, undefined, NOW);
    expect(s).toMatchObject({ originalTransactionId: '1000', willRenew: true, renewsAt: at(30), revoked: false, expired: false });
    expect(isPro(stored(s), NOW)).toBe(true);
  });

  it('reads renewal info and API status', () => {
    const off = snapshotFrom(tx(), { autoRenewStatus: 0 }, 1, NOW);
    expect(off).toMatchObject({ willRenew: false, renewsAt: null });
    const retry = snapshotFrom(tx({ expiresDate: at(-2).getTime() }), { autoRenewStatus: 1, isInBillingRetryPeriod: true }, 3, NOW);
    expect(retry.isInBillingRetry).toBe(true);
    expect(isPro(stored(retry), NOW)).toBe(true);
    const grace = snapshotFrom(tx({ expiresDate: at(-1).getTime() }), { gracePeriodExpiresDate: at(5).getTime() }, undefined, NOW);
    expect(grace.isInBillingRetry).toBe(true);
    expect(isPro(stored(snapshotFrom(tx(), undefined, 2, NOW)), NOW)).toBe(false);
    expect(isPro(stored(snapshotFrom(tx(), undefined, 5, NOW)), NOW)).toBe(false);
    expect(isPro(stored(snapshotFrom(tx({ revocationDate: NOW.getTime() }), undefined, undefined, NOW)), NOW)).toBe(false);
  });

  it('never replaces a longer active subscription with a shorter or expired one', () => {
    const current = stored(snapshotFrom(tx({ originalTransactionId: 'A', expiresDate: at(300).getTime() }), undefined, undefined, NOW));
    expect(nextEntitlement(current, snapshotFrom(tx({ originalTransactionId: 'B', expiresDate: at(20).getTime() }), undefined, undefined, NOW), NOW)).toBeNull();
    expect(nextEntitlement(current, snapshotFrom(tx({ originalTransactionId: 'B', expiresDate: at(-1).getTime() }), undefined, undefined, NOW), NOW)).toBeNull();
    const longer = nextEntitlement(current, snapshotFrom(tx({ originalTransactionId: 'B', expiresDate: at(400).getTime() }), undefined, undefined, NOW), NOW);
    expect(longer?.originalTransactionId).toBe('B');
    // An expired subscription gives way to anything.
    const lapsed = stored(snapshotFrom(tx({ originalTransactionId: 'A', expiresDate: at(-10).getTime() }), undefined, undefined, NOW));
    expect(nextEntitlement(lapsed, snapshotFrom(tx({ originalTransactionId: 'B', expiresDate: at(-1).getTime() }), undefined, undefined, NOW), NOW)?.originalTransactionId).toBe('B');
  });

  it('never rolls the same subscription back to an earlier period', () => {
    const current = stored(snapshotFrom(tx({ expiresDate: at(30).getTime() }), undefined, undefined, NOW));
    expect(nextEntitlement(current, snapshotFrom(tx({ expiresDate: at(-5).getTime(), revocationDate: NOW.getTime() }), undefined, undefined, NOW), NOW)).toBeNull();
    const renewed = nextEntitlement(current, snapshotFrom(tx({ expiresDate: at(60).getTime(), productId: 'app.nameshake.ios.pro.monthly' }), undefined, undefined, NOW), NOW);
    expect(renewed).toMatchObject({ expiresAt: at(60), productId: 'app.nameshake.ios.pro.monthly' });
  });

  it('maps notifications: billing retry keeps Pro, expiry/refund/revoke end it', () => {
    const t = tx({ expiresDate: at(-1).getTime() });
    const current = stored(snapshotFrom(tx({ expiresDate: at(-1).getTime() }), undefined, undefined, NOW));
    const fail = notificationSnapshot('DID_FAIL_TO_RENEW', t, { autoRenewStatus: 1 }, undefined, NOW)!;
    expect(isPro(nextEntitlement(current, fail, NOW)!, NOW)).toBe(true);
    for (const type of ['EXPIRED', 'GRACE_PERIOD_EXPIRED', 'REFUND', 'REVOKE']) {
      const s = notificationSnapshot(type, tx(), undefined, undefined, NOW)!;
      const next = nextEntitlement(stored(snapshotFrom(tx(), undefined, undefined, NOW)), s, NOW)!;
      expect(next, type).toMatchObject({ plan: 'free', willRenew: false, isInBillingRetry: false });
      expect(isPro(next, NOW)).toBe(false);
    }
    expect(notificationSnapshot('TEST', tx(), undefined, undefined, NOW)).toBeNull();
    expect(notificationSnapshot('PRICE_INCREASE', tx(), undefined, undefined, NOW)).toBeNull();
  });
});
