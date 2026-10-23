import type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import type { Entitlement } from '../../generated/prisma/client';
import { isPro } from '../../subscriptions/entitlements.service';

/** App Store subscription status (App Store Server API `Status`). */
export const AppleStatus = { Active: 1, Expired: 2, BillingRetry: 3, GracePeriod: 4, Revoked: 5 } as const;

/** What one Apple subscription (an originalTransactionId) currently grants. */
export interface SubscriptionSnapshot {
  originalTransactionId: string;
  productId: string;
  environment: string;
  expiresAt: Date | null;
  /** Refunded or revoked (Family Sharing removed): no access, right now. */
  revoked: boolean;
  /** Apple says it has ended (EXPIRED, GRACE_PERIOD_EXPIRED, status 2). */
  expired: boolean;
  willRenew: boolean;
  renewsAt: Date | null;
  /** Billing retry or billing grace period: Pro stays on until Apple reports the end. */
  isInBillingRetry: boolean;
}

export type EntitlementData = Pick<
  Entitlement,
  'plan' | 'productId' | 'originalTransactionId' | 'expiresAt' | 'willRenew' | 'renewsAt' | 'environment' | 'isInBillingRetry'
>;

const date = (ms: number | undefined) => (ms === undefined || ms === null ? null : new Date(ms));

/**
 * Builds a snapshot from a verified transaction, plus the renewal info and status when Apple supplied
 * them (App Store Server API, notifications). Without renewal info (a bare StoreKit transaction) an
 * unexpired subscription is assumed to renew, like the mock server.
 */
export function snapshotFrom(
  tx: JWSTransactionDecodedPayload,
  renewal: JWSRenewalInfoDecodedPayload | undefined,
  status: number | undefined,
  now = new Date(),
): SubscriptionSnapshot {
  const expiresAt = date(tx.expiresDate);
  const revoked = tx.revocationDate !== undefined || status === AppleStatus.Revoked;
  const expired = status === AppleStatus.Expired;
  const graceUntil = date(renewal?.gracePeriodExpiresDate);
  const isInBillingRetry =
    !revoked &&
    !expired &&
    (status === AppleStatus.BillingRetry ||
      status === AppleStatus.GracePeriod ||
      renewal?.isInBillingRetryPeriod === true ||
      (graceUntil !== null && graceUntil > now));
  const active = !revoked && !expired && (isInBillingRetry || (expiresAt !== null && expiresAt > now));
  const willRenew = renewal ? active && renewal.autoRenewStatus === 1 : active;
  return {
    originalTransactionId: tx.originalTransactionId ?? tx.transactionId ?? '',
    productId: tx.productId ?? '',
    environment: String(tx.environment ?? ''),
    expiresAt,
    revoked,
    expired,
    willRenew,
    renewsAt: willRenew ? (date(renewal?.renewalDate) ?? expiresAt) : null,
    isInBillingRetry,
  };
}

export function snapshotGrantsPro(s: SubscriptionSnapshot, now = new Date()): boolean {
  return isPro(toData(s), now);
}

function toData(s: SubscriptionSnapshot): EntitlementData {
  const ended = s.revoked || s.expired;
  return {
    plan: ended ? 'free' : 'pro',
    productId: s.productId,
    originalTransactionId: s.originalTransactionId,
    expiresAt: s.expiresAt,
    willRenew: ended ? false : s.willRenew,
    renewsAt: ended ? null : s.renewsAt,
    environment: s.environment,
    isInBillingRetry: ended ? false : s.isInBillingRetry,
  };
}

/**
 * Account-level merge. Returns the entitlement to store, or null to keep the current one:
 * - another subscription that is still active never gives way to one that ends sooner (an
 *   upgraded-from plan or a refund replayed by `Transaction.updates`) — mock server rule;
 * - for the same subscription, an older transaction (an earlier renewal, a refund of a past period)
 *   never rolls a later expiry back.
 */
export function nextEntitlement(current: EntitlementData | null, s: SubscriptionSnapshot, now = new Date()): EntitlementData | null {
  const incoming = toData(s);
  if (!current) return incoming;
  const sameSubscription = current.originalTransactionId === s.originalTransactionId;
  const currentEnds = current.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY;
  const incomingEnds = s.expiresAt?.getTime() ?? Number.POSITIVE_INFINITY;

  if (sameSubscription) {
    if (incomingEnds < currentEnds) return null;
    return incoming;
  }
  if (isPro(current, now)) {
    const incomingPro = isPro(incoming, now);
    if (!incomingPro || incomingEnds <= currentEnds) return null;
  }
  return incoming;
}

/** True when storing `next` would change anything visible. */
export function entitlementChanged(current: EntitlementData | null, next: EntitlementData): boolean {
  if (!current) return true;
  const t = (d: Date | null) => d?.getTime() ?? null;
  return (
    current.plan !== next.plan ||
    current.productId !== next.productId ||
    current.originalTransactionId !== next.originalTransactionId ||
    t(current.expiresAt) !== t(next.expiresAt) ||
    current.willRenew !== next.willRenew ||
    t(current.renewsAt) !== t(next.renewsAt) ||
    current.environment !== next.environment ||
    current.isInBillingRetry !== next.isInBillingRetry
  );
}
