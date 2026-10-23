import { type CanActivate, type ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Response } from 'express';
import { ApiError } from './api-error';
import { clientIp, type MetlyRequest } from './request';

export interface Budget {
  limit: number;
  windowSeconds: number;
  /** Keyed per authenticated user (default) or per client IP. */
  by: 'user' | 'ip';
  /** Extra key part from a route param (share-back limits are per card). */
  param?: string;
}

/** Budgets from openapi `info.description` § Rate limits. */
export const BUDGETS = {
  default: { limit: 600, windowSeconds: 60, by: 'user' },
  publicDefault: { limit: 120, windowSeconds: 60, by: 'ip' },
  auth: { limit: 10, windowSeconds: 60, by: 'ip' },
  sync: { limit: 60, windowSeconds: 60, by: 'user' },
  connect: { limit: 30, windowSeconds: 60, by: 'user' },
  publicCard: { limit: 120, windowSeconds: 60, by: 'ip' },
  shareBackPerIp: { limit: 5, windowSeconds: 3600, by: 'ip', param: 'slug' },
  analytics: { limit: 60, windowSeconds: 60, by: 'ip' },
  deferredClaim: { limit: 10, windowSeconds: 3600, by: 'ip' },
  export: { limit: 3, windowSeconds: 86_400, by: 'user' },
} satisfies Record<string, Budget>;

export type BudgetName = keyof typeof BUDGETS;

const RATE_LIMIT = 'metly:rate-limit';
/** Applies one or more named budgets to a route (all must have room). */
export const RateLimit = (...names: BudgetName[]) => SetMetadata(RATE_LIMIT, names);
const SKIP_RATE_LIMIT = 'metly:no-rate-limit';
export const NoRateLimit = () => SetMetadata(SKIP_RATE_LIMIT, true);

/**
 * Fixed-window counters held in memory. Correct for a single instance; with several instances behind a
 * load balancer the effective limit multiplies — move the store to Redis/Postgres before scaling out.
 */
export class RateLimitStore {
  private readonly windows = new Map<string, { count: number; resetAt: number }>();
  private lastSweep = Date.now();

  hit(key: string, budget: Budget, now = Date.now()) {
    this.sweep(now);
    let window = this.windows.get(key);
    if (!window || window.resetAt <= now) {
      window = { count: 0, resetAt: now + budget.windowSeconds * 1000 };
      this.windows.set(key, window);
    }
    window.count += 1;
    return { allowed: window.count <= budget.limit, remaining: Math.max(0, budget.limit - window.count), resetAt: window.resetAt };
  }

  /** Counts against a budget without a request (e.g. the per-card share-back cap). */
  check(key: string, budget: Budget, now = Date.now()) {
    return this.hit(key, budget, now).allowed;
  }

  private sweep(now: number) {
    if (now - this.lastSweep < 60_000) return;
    this.lastSweep = now;
    for (const [key, window] of this.windows) if (window.resetAt <= now) this.windows.delete(key);
  }

  reset() {
    this.windows.clear();
  }
}

@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly store: RateLimitStore,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    if (context.getType() !== 'http') return true;
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(SKIP_RATE_LIMIT, targets)) return true;
    const request = context.switchToHttp().getRequest<MetlyRequest>();
    const response = context.switchToHttp().getResponse<Response>();
    const names = this.reflector.getAllAndOverride<BudgetName[]>(RATE_LIMIT, targets) ?? [request.user ? 'default' : 'publicDefault'];

    let tightest: { budget: Budget; remaining: number; resetAt: number } | undefined;
    for (const name of names) {
      const budget: Budget = BUDGETS[name];
      const subject = budget.by === 'user' && request.user ? `u:${request.user.id}` : `ip:${clientIp(request)}`;
      const extra = budget.param ? `:${String(request.params[budget.param] ?? '')}` : '';
      const result = this.store.hit(`${name}:${subject}${extra}`, budget);
      if (!tightest || result.remaining < tightest.remaining) tightest = { budget, ...result };
      if (!result.allowed) {
        const retryAfter = Math.max(1, Math.ceil((result.resetAt - Date.now()) / 1000));
        throw new ApiError(429, 'rate_limited', 'Too many requests. Try again shortly.', undefined, {
          'Retry-After': String(retryAfter),
          'X-RateLimit-Limit': String(budget.limit),
          'X-RateLimit-Remaining': '0',
          'X-RateLimit-Reset': String(Math.ceil(result.resetAt / 1000)),
        });
      }
    }
    if (tightest) {
      response.setHeader('X-RateLimit-Limit', String(tightest.budget.limit));
      response.setHeader('X-RateLimit-Remaining', String(tightest.remaining));
      response.setHeader('X-RateLimit-Reset', String(Math.ceil(tightest.resetAt / 1000)));
    }
    return true;
  }
}
