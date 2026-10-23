import { type CallHandler, type ExecutionContext, Injectable, type NestInterceptor } from '@nestjs/common';
import type { Response } from 'express';
import { from, type Observable, of, throwError } from 'rxjs';
import { catchError, mergeMap } from 'rxjs/operators';
import type { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ApiError } from './api-error';
import { sha256 } from './crypto';
import { clientIp, type MetlyRequest } from './request';

const IN_PROGRESS = 0;

/**
 * `Idempotency-Key` on POST/PATCH: the first response is stored for 24 h per (user or IP, key) and
 * replayed for retries; the same key with a different body → 409 idempotency_conflict.
 * Server errors (5xx) and rate limits are not stored, so they can be retried.
 */
@Injectable()
export class IdempotencyInterceptor implements NestInterceptor {
  constructor(private readonly prisma: PrismaService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();
    const request = context.switchToHttp().getRequest<MetlyRequest>();
    const response = context.switchToHttp().getResponse<Response>();
    const key = request.header('idempotency-key');
    if (!key || !['POST', 'PATCH'].includes(request.method)) return next.handle();
    if (key.length > 255) return throwError(() => ApiError.badRequest('Idempotency-Key is longer than 255 characters.'));

    const scope = request.user ? `u:${request.user.id}` : `ip:${clientIp(request)}`;
    const requestHash = sha256(`${request.method} ${request.originalUrl.split('?')[0]} ${JSON.stringify(request.body ?? null)}`);

    return from(this.claim(scope, key, requestHash)).pipe(
      mergeMap((stored) => {
        if (stored) {
          response.status(stored.status);
          return of(stored.body ?? undefined);
        }
        return next.handle().pipe(
          mergeMap((body) => from(this.save(scope, key, response.statusCode, body)).pipe(mergeMap(() => of(body)))),
          catchError((error: unknown) => {
            const keep = error instanceof ApiError && error.status < 500 && error.status !== 429 && error.status !== 401;
            const settle = keep
              ? this.save(scope, key, (error as ApiError).status, (error as ApiError).toBody(), true)
              : this.release(scope, key);
            return from(settle).pipe(mergeMap(() => throwError(() => error)));
          }),
        );
      }),
    );
  }

  /** Reserves the key, or returns the stored response to replay. */
  private async claim(scope: string, key: string, requestHash: string) {
    const inserted = await this.prisma.$executeRaw`
      INSERT INTO idempotency_records (scope, key, request_hash, status, created_at)
      VALUES (${scope}, ${key}, ${requestHash}, ${IN_PROGRESS}, now())
      ON CONFLICT (scope, key) DO UPDATE
        SET request_hash = EXCLUDED.request_hash, status = ${IN_PROGRESS}, body = NULL, created_at = now()
        WHERE idempotency_records.created_at < now() - interval '24 hours'`;
    if (inserted === 1) return null;
    const existing = await this.prisma.idempotencyRecord.findUnique({ where: { scope_key: { scope, key } } });
    if (!existing) return null;
    if (existing.requestHash !== requestHash) {
      throw new ApiError(409, 'idempotency_conflict', 'This Idempotency-Key was used for a different request.');
    }
    if (existing.status === IN_PROGRESS) {
      throw new ApiError(409, 'conflict', 'The same request is still being processed.');
    }
    const body = existing.body as { error?: Record<string, unknown>; value?: unknown } | null;
    if (body?.error) {
      const e = body.error as { code: ApiError['code']; message: string; details?: Record<string, string> };
      throw new ApiError(existing.status, e.code, e.message, e.details);
    }
    return { status: existing.status, body: body?.value };
  }

  private async save(scope: string, key: string, status: number, body: unknown, isError = false) {
    const stored = (isError ? { error: body } : { value: body ?? null }) as Prisma.InputJsonValue;
    await this.prisma.idempotencyRecord.update({ where: { scope_key: { scope, key } }, data: { status, body: stored } });
  }

  private async release(scope: string, key: string) {
    await this.prisma.idempotencyRecord.deleteMany({ where: { scope, key, status: IN_PROGRESS } });
  }
}
