import { Injectable } from '@nestjs/common';
import { iso } from '../common/time';
import type { Entitlement } from '../generated/prisma/client';
import { PrismaService, type Tx } from '../prisma/prisma.service';

export interface PlanLimits {
  maxCards: number | null;
  maxOpenFollowUps: number | null;
  maxActiveEvents: number | null;
}

export const FREE_LIMITS: PlanLimits = { maxCards: 2, maxOpenFollowUps: 5, maxActiveEvents: 1 };
export const PRO_LIMITS: PlanLimits = { maxCards: null, maxOpenFollowUps: null, maxActiveEvents: null };

/** StoreKit product ids the app sells (`Metly/Metly.storekit`, `ProProduct.swift`). */
export const PRO_PRODUCT_IDS = ['com.metly.app.pro.yearly', 'com.metly.app.pro.monthly'] as const;
export type ProProductId = (typeof PRO_PRODUCT_IDS)[number];
export const isProProductId = (id: string | null | undefined): id is ProProductId =>
  (PRO_PRODUCT_IDS as readonly string[]).includes(id ?? '');

/** `Entitlement.environment` values on the wire (LocalTesting is reported as Xcode). */
const WIRE_ENVIRONMENTS = new Set(['Production', 'Sandbox', 'Xcode']);
const wireEnvironment = (env: string | null | undefined) =>
  env === 'LocalTesting' ? 'Xcode' : env && WIRE_ENVIRONMENTS.has(env) ? env : undefined;

/** Pro stays on through billing retry; the App Store tells us (EXPIRED / GRACE_PERIOD_EXPIRED) when it ends. */
export function isPro(e: Pick<Entitlement, 'plan' | 'expiresAt' | 'isInBillingRetry'> | null | undefined, now = new Date()): boolean {
  if (!e || e.plan !== 'pro') return false;
  if (e.isInBillingRetry) return true;
  return e.expiresAt === null || e.expiresAt > now;
}

@Injectable()
export class EntitlementsService {
  constructor(private readonly prisma: PrismaService) {}

  async get(userId: string, tx: Tx = this.prisma): Promise<Entitlement | null> {
    return tx.entitlement.findUnique({ where: { userId } });
  }

  async limits(userId: string, tx: Tx = this.prisma): Promise<{ pro: boolean; limits: PlanLimits }> {
    const pro = isPro(await this.get(userId, tx));
    return { pro, limits: pro ? PRO_LIMITS : FREE_LIMITS };
  }

  toWire(e: Entitlement | null, now = new Date()) {
    const pro = isPro(e, now);
    const environment = wireEnvironment(e?.environment);
    return {
      plan: pro ? 'pro' : 'free',
      ...(e && isProProductId(e.productId) ? { productId: e.productId } : {}),
      ...(e?.expiresAt ? { expiresAt: iso(e.expiresAt) } : {}),
      willRenew: e?.willRenew ?? false,
      ...(e?.renewsAt ? { renewsAt: iso(e.renewsAt) } : {}),
      ...(e?.originalTransactionId ? { originalTransactionId: e.originalTransactionId } : {}),
      ...(environment ? { environment } : {}),
      isInBillingRetry: e?.isInBillingRetry ?? false,
      limits: pro ? PRO_LIMITS : FREE_LIMITS,
    };
  }

  async wire(userId: string, tx: Tx = this.prisma) {
    return this.toWire(await this.get(userId, tx));
  }
}
