import type { NestExpressApplication } from '@nestjs/platform-express';
import helmet from 'helmet';
import { edgeProxyClientIp } from './common/edge-proxy';
import type { Env } from './config/env';

/** HTTP settings shared by main.ts and the e2e tests. */
export function configureApp(app: NestExpressApplication, env: Pick<Env, 'TRUST_PROXY' | 'EDGE_PROXY_SECRET'>): NestExpressApplication {
  // Read the client IP (rate limits) from X-Forwarded-For only as far as our own proxies go.
  app.set('trust proxy', env.TRUST_PROXY);
  app.use(edgeProxyClientIp(env.EDGE_PROXY_SECRET));
  app.disable('x-powered-by');
  app.use(helmet({ contentSecurityPolicy: false, crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.useBodyParser('json', { limit: '2mb' });
  app.useBodyParser('urlencoded', { extended: false, limit: '64kb' });
  app.enableShutdownHooks();
  return app;
}
