import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';

/** HTTP settings shared by main.ts and the e2e tests. */
export function configureApp(app: NestExpressApplication): NestExpressApplication {
  // Behind the platform's load balancer: trust X-Forwarded-For for client IPs (rate limits).
  app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.useBodyParser('json', { limit: '2mb' });
  app.useBodyParser('urlencoded', { extended: false, limit: '64kb' });
  app.enableShutdownHooks();
  return app;
}
