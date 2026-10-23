import { type DynamicModule, Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { LoggerModule } from 'nestjs-pino';
import { AccountModule } from './account/account.module';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { CommonModule } from './common/common.module';
import { ErrorFilter } from './common/error.filter';
import { IdempotencyInterceptor } from './common/idempotency.interceptor';
import { RateLimitGuard } from './common/rate-limit';
import { ConfigModule } from './config/config.module';
import type { Env } from './config/env';
import { ConnectModule } from './connect/connect.module';
import { HealthController } from './health/health.controller';
import { MediaModule } from './media/media.module';
import { PlatformModule } from './platform/platform.module';
import { PushModule } from './push/push.module';
import { PrismaModule } from './prisma/prisma.module';
import { RealtimeModule } from './realtime/realtime.module';
import { RecordsModule } from './records/records.module';
import { SyncModule } from './sync/sync.module';
import { WebModule } from './web/web.module';

@Module({})
export class AppModule {
  static forRoot(env: Env): DynamicModule {
    return {
      module: AppModule,
      imports: [
        ConfigModule.forRoot(env),
        LoggerModule.forRoot({
          pinoHttp: {
            level: env.LOG_LEVEL,
            genReqId: (req) => (req.headers['x-request-id'] as string | undefined) ?? `req_${crypto.randomUUID()}`,
            redact: ['req.headers.authorization', 'req.headers.cookie', 'req.headers["x-removal-token"]'],
            autoLogging: { ignore: (req) => (req.url ?? '').startsWith('/health') },
            // Never log bodies, tokens or full headers: method, path, status and timing are enough.
            serializers: {
              req: (req: { id: unknown; method: string; url: string }) => ({ id: req.id, method: req.method, url: req.url?.split('?')[0] }),
              res: (res: { statusCode: number }) => ({ statusCode: res.statusCode }),
            },
          },
        }),
        PrismaModule,
        CommonModule,
        AuthModule,
        RealtimeModule,
        RecordsModule,
        SyncModule,
        AccountModule,
        PushModule,
        ConnectModule,
        WebModule,
        PlatformModule,
        MediaModule,
      ],
      controllers: [HealthController],
      providers: [
        { provide: APP_GUARD, useClass: AuthGuard },
        { provide: APP_GUARD, useClass: RateLimitGuard },
        { provide: APP_INTERCEPTOR, useClass: IdempotencyInterceptor },
        { provide: APP_FILTER, useClass: ErrorFilter },
      ],
    };
  }
}
