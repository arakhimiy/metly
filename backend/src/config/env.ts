import { z } from 'zod';

const optional = z
  .string()
  .optional()
  .transform((v) => (v && v.trim().length > 0 ? v.trim() : undefined));

const list = z
  .string()
  .optional()
  .transform((v) =>
    (v ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );

/** PEM values arrive from secret stores with literal "\n"; restore real newlines. */
const pem = optional.transform((v) => v?.replace(/\\n/g, '\n'));

const schema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(3000),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
    DATABASE_URL: z.string().min(1),
    WEB_BASE_URL: z.url(),
    API_BASE_URL: z.url(),

    JWT_SECRET: z.string().min(32),
    ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(300).max(3600).default(1800),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(365).default(60),

    APPLE_BUNDLE_IDS: list,
    APPLE_TEAM_ID: optional,
    APPLE_SIGNIN_KEY_ID: optional,
    APPLE_SIGNIN_PRIVATE_KEY: pem,
    GOOGLE_CLIENT_IDS: list,
    DEV_AUTH_ENABLED: z
      .string()
      .optional()
      .transform((v) => v === 'true'),

    APNS_KEY_ID: optional,
    APNS_TEAM_ID: optional,
    APNS_PRIVATE_KEY: pem,
    APNS_TOPIC: z.string().default('app.tanishly.ios'),

    APP_STORE_ISSUER_ID: optional,
    APP_STORE_KEY_ID: optional,
    APP_STORE_PRIVATE_KEY: pem,
    APP_STORE_APP_APPLE_ID: optional,
    APP_STORE_ENVIRONMENT: z.enum(['Production', 'Sandbox', 'Xcode', 'LocalTesting']).default('Sandbox'),

    PASS_TYPE_IDENTIFIER: z.string().default('pass.app.tanishly.ios.card'),
    PASS_TEAM_ID: optional,
    PASS_CERT_PEM: pem,
    PASS_KEY_PEM: pem,
    PASS_KEY_PASSPHRASE: optional,
    PASS_WWDR_PEM: pem,

    S3_ENDPOINT: optional,
    S3_REGION: z.string().default('auto'),
    S3_BUCKET: optional,
    S3_ACCESS_KEY_ID: optional,
    S3_SECRET_ACCESS_KEY: optional,
    S3_PUBLIC_BASE_URL: optional,

    TELEGRAM_BOT_USERNAME: z.string().default('TanishlyBot'),
    TELEGRAM_BOT_TOKEN: optional,
    TELEGRAM_WEBHOOK_SECRET: optional,

    APP_STORE_ID: optional,
    /** "Get the app" link before the App Store listing exists, e.g. the TestFlight public link. */
    APP_DOWNLOAD_URL: optional,

    /** Transactional mail (data export links). Empty → exports stay queued. */
    RESEND_API_KEY: optional,
    MAIL_FROM: z.string().default('Tanishly <no-reply@tanishly.app>'),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV !== 'production') return;
    // Refuse to boot production with settings that are only safe locally.
    if (env.DEV_AUTH_ENABLED) {
      ctx.addIssue({ code: 'custom', path: ['DEV_AUTH_ENABLED'], message: 'must be false in production' });
    }
    if (/change-me/.test(env.JWT_SECRET)) {
      ctx.addIssue({ code: 'custom', path: ['JWT_SECRET'], message: 'is still the example value' });
    }
    if (env.APPLE_BUNDLE_IDS.length === 0) {
      ctx.addIssue({ code: 'custom', path: ['APPLE_BUNDLE_IDS'], message: 'is required in production' });
    }
    if (env.APP_DOWNLOAD_URL && !env.APP_DOWNLOAD_URL.startsWith('https://')) {
      ctx.addIssue({ code: 'custom', path: ['APP_DOWNLOAD_URL'], message: 'must be https in production' });
    }
    for (const key of ['WEB_BASE_URL', 'API_BASE_URL'] as const) {
      if (!env[key].startsWith('https://')) {
        ctx.addIssue({ code: 'custom', path: [key], message: 'must be https in production' });
      }
    }
  });

export type Env = z.infer<typeof schema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const lines = parsed.error.issues.map((i) => `  ${i.path.join('.')}: ${i.message}`);
    throw new Error(`Invalid environment:\n${lines.join('\n')}`);
  }
  return parsed.data;
}

/** Where "Get the app" leads: the App Store listing, else the pre-release link (TestFlight), else nowhere. */
export function appDownloadUrl(env: Pick<Env, 'APP_STORE_ID' | 'APP_DOWNLOAD_URL'>): string | undefined {
  if (env.APP_STORE_ID) return `https://apps.apple.com/app/id${encodeURIComponent(env.APP_STORE_ID)}`;
  return env.APP_DOWNLOAD_URL;
}

/** Injection token for the parsed environment. */
export const ENV = Symbol('ENV');
