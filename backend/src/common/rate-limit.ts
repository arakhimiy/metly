import { type CanActivate, type ExecutionContext, Injectable, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Response } from 'express';
import { ENV, type Env } from '../config/env';
import { PrismaService } from '../prisma/prisma.service';
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

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  /** Epoch milliseconds when the current window ends. */
  resetAt: number;
}

/**
 * Fixed-window counters. `PostgresRateLimitStore` is the default: every instance behind the load
 * balancer shares one count per key. `MemoryRateLimitStore` is per process (single instance or tests);
 * pick it with `RATE_LIMIT_STORE=memory`.
 */
export abstract class RateLimitStore {
  abstract hit(key: string, budget: Budget, now?: number): Promise<RateLimitResult>;

  /** Counts against a budget without a request (e.g. the per-card share-back cap). */
  async check(key: string, budget: Budget, now = Date.now()): Promise<boolean> {
    return (await this.hit(key, budget, now)).allowed;
  }

  /** Drops every counter (tests). */
  abstract reset(): Promise<void>;
}

export class MemoryRateLimitStore extends RateLimitStore {
  private readonly windows = new Map<string, { count: number; resetAt: number }>();
  private lastSweep = Date.now();

  async hit(key: string, budget: Budget, now = Date.now()): Promise<RateLimitResult> {
    this.sweep(now);
    let window = this.windows.get(key);
    if (!window || window.resetAt <= now) {
      window = { count: 0, resetAt: now + budget.windowSeconds * 1000 };
      this.windows.set(key, window);
    }
    window.count += 1;
    return { allowed: window.count <= budget.limit, remaining: Math.max(0, budget.limit - window.count), resetAt: window.resetAt };
  }

  private sweep(now: number) {
    if (now - this.lastSweep < 60_000) return;
    this.lastSweep = now;
    for (const [key, window] of this.windows) if (window.resetAt <= now) this.windows.delete(key);
  }

  async reset() {
    this.windows.clear();
  }
}

/**
 * One atomic upsert per budget check on the UNLOGGED `rate_limit_windows` table (no WAL, so it costs
 * about as much as an in-memory hash on the database). Expired rows are reused in place and swept by
 * the daily purge job.
 */
export class PostgresRateLimitStore extends RateLimitStore {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async hit(key: string, budget: Budget, now = Date.now()): Promise<RateLimitResult> {
    const nowAt = new Date(now);
    const resetAt = new Date(now + budget.windowSeconds * 1000);
    const rows = await this.prisma.$queryRaw<{ count: number; reset_at: Date }[]>`
      INSERT INTO rate_limit_windows (key, count, reset_at) VALUES (${key}, 1, ${resetAt})
      ON CONFLICT (key) DO UPDATE SET
        count    = CASE WHEN rate_limit_windows.reset_at <= ${nowAt} THEN 1 ELSE rate_limit_windows.count + 1 END,
        reset_at = CASE WHEN rate_limit_windows.reset_at <= ${nowAt} THEN EXCLUDED.reset_at ELSE rate_limit_windows.reset_at END
      RETURNING count, reset_at`;
    const row = rows[0];
    const count = Number(row?.count ?? 1);
    return { allowed: count <= budget.limit, remaining: Math.max(0, budget.limit - count), resetAt: (row?.reset_at ?? resetAt).getTime() };
  }

  async reset() {
    await this.prisma.$executeRaw`TRUNCATE rate_limit_windows`;
  }
}

/** Nest provider: the store named by `RATE_LIMIT_STORE`. */
export const rateLimitStoreProvider = {
  provide: RateLimitStore,
  inject: [ENV, PrismaService],
  useFactory: (env: Env, prisma: PrismaService): RateLimitStore =>
    env.RATE_LIMIT_STORE === 'memory' ? new MemoryRateLimitStore() : new PostgresRateLimitStore(prisma),
};

@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly store: RateLimitStore,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
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
      const result = await this.store.hit(`${name}:${subject}${extra}`, budget);
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
