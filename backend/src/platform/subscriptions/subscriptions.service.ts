import { Injectable, Logger } from '@nestjs/common';
import type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import { z } from 'zod';
import { ApiError } from '../../common/api-error';
import { parse } from '../../common/validate';
import type { Entitlement } from '../../generated/prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { RecordsService, type WriteContext } from '../../records/records.service';
import { EntitlementsService, FREE_LIMITS, isPro, isProProductId } from '../../subscriptions/entitlements.service';
import { AppStoreGateway } from './app-store.gateway';
import { entitlementChanged, nextEntitlement, type SubscriptionSnapshot, snapshotFrom } from './entitlement-state';

const VerifyBody = z.object({
  signedTransaction: z.string().min(1).max(20_000),
  appAccountToken: z.uuid().nullish(),
});

const NotificationBody = z.object({ signedPayload: z.string().min(1).max(100_000) });

/** Notification types that change what a subscription grants; the rest are only recorded. */
const STATE_TYPES = new Set([
  'SUBSCRIBED',
  'DID_RENEW',
  'DID_CHANGE_RENEWAL_STATUS',
  'DID_CHANGE_RENEWAL_PREF',
  'DID_FAIL_TO_RENEW',
  'EXPIRED',
  'GRACE_PERIOD_EXPIRED',
  'REFUND',
  'REVOKE',
  'REFUND_REVERSED',
  'OFFER_REDEEMED',
  'RENEWAL_EXTENDED',
]);

interface NotificationRecord {
  notificationUUID: string;
  notificationType: string;
  subtype: string | null;
  originalTransactionId: string | null;
}

/** Applies a notification's meaning on top of the transaction/renewal snapshot. */
export function notificationSnapshot(
  type: string,
  tx: JWSTransactionDecodedPayload,
  renewal: JWSRenewalInfoDecodedPayload | undefined,
  status: number | undefined,
  now = new Date(),
): SubscriptionSnapshot | null {
  if (!STATE_TYPES.has(type)) return null;
  const s = snapshotFrom(tx, renewal, status, now);
  switch (type) {
    case 'EXPIRED':
    case 'GRACE_PERIOD_EXPIRED':
      return { ...s, expired: true, willRenew: false, renewsAt: null, isInBillingRetry: false };
    case 'REFUND':
    case 'REVOKE':
      return { ...s, revoked: true, willRenew: false, renewsAt: null, isInBillingRetry: false };
    case 'REFUND_REVERSED':
      return { ...s, revoked: false };
    case 'DID_FAIL_TO_RENEW':
      // Billing retry (and its grace period) keeps Pro until EXPIRED / GRACE_PERIOD_EXPIRED.
      return s.revoked || s.expired ? s : { ...s, isInBillingRetry: true };
    default:
      return s;
  }
}

/**
 * StoreKit 2 purchases → entitlements: `POST /v1/subscriptions/verify` (from the app) and App Store
 * Server Notifications V2 (`POST /v1/webhooks/app-store`). An originalTransactionId unlocks one
 * account. Entitlement changes bump the owner's seq and emit `user.changed` (sync.available); losing
 * Pro makes cards beyond the 2 lowest sortOrder read-only, gaining it clears that.
 */
@Injectable()
export class SubscriptionsService {
  private readonly logger = new Logger(SubscriptionsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    private readonly entitlements: EntitlementsService,
    private readonly appStore: AppStoreGateway,
  ) {}

  async verify(userId: string, body: unknown) {
    const input = parse(VerifyBody, body);
    const environment = this.peekEnvironment(input.signedTransaction);
    // Production / Sandbox purchases are confirmed with the App Store Server API, so they need its
    // credentials. Local StoreKit testing (Xcode) is accepted outside production without them.
    if (!this.appStore.acceptsEnvironment(environment)) {
      throw ApiError.badRequest(`Purchases from the ${environment || 'unknown'} environment are not accepted here.`);
    }
    if (!this.appStore.isLocalEnvironment(environment) && !this.appStore.apiConfigured) {
      throw ApiError.unavailable('Purchases cannot be verified right now.');
    }
    const tx = await this.appStore.verifyTransaction(input.signedTransaction);
    const originalTransactionId = tx.originalTransactionId;
    if (!originalTransactionId) throw ApiError.badRequest('The transaction has no originalTransactionId.');
    if (!isProProductId(tx.productId)) throw ApiError.badRequest('This product does not unlock Metly Pro.');
    await this.assertAccountToken(tx, userId);

    let snapshot: SubscriptionSnapshot | null = null;
    try {
      const status = await this.appStore.subscriptionStatus(originalTransactionId, String(tx.environment), tx.bundleId ?? '');
      if (status && isProProductId(status.transaction.productId)) {
        snapshot = snapshotFrom(status.transaction, status.renewal, status.status);
      }
    } catch (error) {
      if (error instanceof ApiError && error.status === 400) throw error;
      // The signed transaction is Apple-signed on its own; notifications correct any drift.
      this.logger.warn({ err: error, originalTransactionId }, 'App Store Server API unavailable; using the signed transaction');
    }
    // An upgraded-from transaction is superseded by the one it was upgraded to.
    if (!snapshot && !tx.isUpgraded) snapshot = snapshotFrom(tx, undefined, undefined);
    const entitlement = snapshot ? await this.apply(userId, snapshot, { strictOwner: true }) : await this.entitlements.get(userId);
    return this.entitlements.toWire(entitlement);
  }

  /** Webhook. Verified, idempotent by notificationUUID; returns once the notification is stored. */
  async handleNotification(body: unknown): Promise<void> {
    const { signedPayload } = parse(NotificationBody, body);
    const notification = await this.appStore.verifyNotification(signedPayload);
    const uuid = notification.notificationUUID;
    if (!uuid) throw ApiError.badRequest('The notification has no notificationUUID.');
    if (await this.prisma.appStoreNotification.findUnique({ where: { notificationUUID: uuid } })) return;

    const type = String(notification.notificationType ?? '');
    const data = notification.data;
    const tx = data?.signedTransactionInfo ? await this.appStore.verifyTransaction(data.signedTransactionInfo) : undefined;
    const renewal =
      data?.signedRenewalInfo && tx
        ? await this.appStore.verifyRenewalInfo(data.signedRenewalInfo, String(tx.environment), tx.bundleId ?? '')
        : undefined;
    const record: NotificationRecord = {
      notificationUUID: uuid,
      notificationType: type,
      subtype: notification.subtype ? String(notification.subtype) : null,
      originalTransactionId: tx?.originalTransactionId ?? null,
    };

    const snapshot = tx && isProProductId(tx.productId) ? notificationSnapshot(type, tx, renewal, data?.status) : null;
    const userId = snapshot && tx ? await this.ownerOf(tx) : null;
    if (!snapshot || !userId) {
      // Nothing to change (TEST, a purchase not linked to an account yet — verify links it later).
      await this.prisma.appStoreNotification.createMany({ data: [record], skipDuplicates: true });
      return;
    }
    await this.apply(userId, snapshot, { strictOwner: false, notification: record });
  }

  /**
   * Stores the merged entitlement and, when Pro was gained or lost, flips card read-only flags.
   * `strictOwner`: 409 when the subscription already unlocks another account (verify); webhooks
   * resolve the owner first, so for them it only guards a race.
   */
  async apply(
    userId: string,
    snapshot: SubscriptionSnapshot,
    opts: { strictOwner: boolean; notification?: NotificationRecord },
    now = new Date(),
  ): Promise<Entitlement | null> {
    const { result } = await this.records.write(userId, async (ctx) => {
      const { tx } = ctx;
      await this.prisma.lockUsers(tx, [userId]);
      const current = await tx.entitlement.findUnique({ where: { userId } });
      if (opts.notification) {
        const stored = await tx.appStoreNotification.createMany({ data: [opts.notification], skipDuplicates: true });
        if (stored.count === 0) return current; // delivered twice concurrently
      }
      const owner = await tx.entitlement.findUnique({ where: { originalTransactionId: snapshot.originalTransactionId } });
      if (owner && owner.userId !== userId) {
        if (opts.strictOwner) throw new ApiError(409, 'conflict', 'This App Store subscription already unlocks another Metly account.');
        return current;
      }
      const next = nextEntitlement(current, snapshot, now);
      if (!next || !entitlementChanged(current, next)) return current;
      const row = await tx.entitlement.upsert({ where: { userId }, create: { userId, ...next }, update: next });
      await this.changed(ctx, userId);
      await this.reconcileCards(ctx, isPro(row, now));
      return row;
    });
    return result;
  }

  /**
   * Safety net for a missed EXPIRED notification: a Pro entitlement past its expiry and not in billing
   * retry becomes Free (cards beyond the limit turn read-only, devices pull).
   */
  async expireLapsed(now = new Date()): Promise<number> {
    const lapsed = await this.prisma.entitlement.findMany({
      where: { plan: 'pro', isInBillingRetry: false, expiresAt: { lt: now } },
      select: { userId: true },
      take: 500,
    });
    let expired = 0;
    for (const { userId } of lapsed) {
      const { result } = await this.records.write(userId, async (ctx) => {
        await this.prisma.lockUsers(ctx.tx, [userId]);
        const current = await ctx.tx.entitlement.findUnique({ where: { userId } });
        if (!current || current.plan !== 'pro' || isPro(current, now)) return false;
        await ctx.tx.entitlement.update({ where: { userId }, data: { plan: 'free', willRenew: false, renewsAt: null } });
        await this.changed(ctx, userId);
        await this.reconcileCards(ctx, false);
        return true;
      });
      if (result) expired++;
    }
    return expired;
  }

  /** Free keeps the 2 lowest-sortOrder cards editable; the rest stay published but read-only. */
  async reconcileCards(ctx: WriteContext, pro: boolean): Promise<number> {
    const { tx, userId } = ctx;
    const cards = await tx.card.findMany({
      where: { userId, deletedAt: null },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }, { id: 'asc' }],
    });
    const editable = FREE_LIMITS.maxCards ?? Number.POSITIVE_INFINITY;
    let flipped = 0;
    for (const [index, card] of cards.entries()) {
      const readOnly = !pro && index >= editable;
      if (card.isReadOnly === readOnly) continue;
      ctx.effects.usersChanged.add(userId);
      const row = await tx.card.update({ where: { id: card.id }, data: { isReadOnly: readOnly, seq: await this.prisma.nextSeq(tx, userId) } });
      await this.records.emitCard(ctx, row);
      flipped++;
    }
    return flipped;
  }

  /** The entitlement is part of every pull: move the cursor and tell the user's devices. */
  private async changed(ctx: WriteContext, userId: string) {
    ctx.effects.usersChanged.add(userId);
    await this.prisma.nextSeq(ctx.tx, userId);
  }

  /** The account a subscription belongs to: the linked one, else the purchase's appAccountToken. */
  private async ownerOf(tx: JWSTransactionDecodedPayload): Promise<string | null> {
    if (tx.originalTransactionId) {
      const linked = await this.prisma.entitlement.findUnique({ where: { originalTransactionId: tx.originalTransactionId }, select: { userId: true } });
      if (linked) return linked.userId;
    }
    const token = tx.appAccountToken?.toLowerCase();
    if (token && z.uuid().safeParse(token).success) {
      const user = await this.prisma.user.findUnique({ where: { id: token }, select: { id: true } });
      if (user) return user.id;
    }
    return null;
  }

  /** `appAccountToken` = the buyer's user id when the app sets it: another live account → 409. */
  private async assertAccountToken(tx: JWSTransactionDecodedPayload, userId: string) {
    const token = tx.appAccountToken?.toLowerCase();
    if (!token || token === userId || !z.uuid().safeParse(token).success) return;
    const other = await this.prisma.user.findUnique({ where: { id: token }, select: { id: true } });
    if (other) throw new ApiError(409, 'conflict', 'This App Store subscription was bought for another Metly account.');
  }

  private peekEnvironment(jws: string): string {
    try {
      const payload = JSON.parse(Buffer.from(jws.split('.')[1] ?? '', 'base64url').toString('utf8')) as { environment?: unknown };
      return typeof payload.environment === 'string' ? payload.environment : '';
    } catch {
      throw ApiError.badRequest('Malformed signed transaction.');
    }
  }
}
