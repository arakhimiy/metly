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

    /**
     * Express `trust proxy`: how far to trust X-Forwarded-For when reading the client IP (rate limits,
     * analytics). A hop count ("1" = one load balancer in front, e.g. Render/Fly/Railway), a comma list
     * of trusted proxy subnets ("loopback, 10.0.0.0/8"), or "false" when clients connect directly.
     * Never "true": that trusts any client-supplied header and lets anyone pick their own IP.
     */
    TRUST_PROXY: z
      .string()
      .default('1')
      .transform((v, ctx) => {
        const value = v.trim();
        if (value === 'false') return false;
        if (/^\d+$/.test(value)) return Number(value);
        if (value === 'true') {
          ctx.addIssue({ code: 'custom', message: 'must be a hop count or a subnet list, not "true"' });
          return z.NEVER;
        }
        return value.split(',').map((s) => s.trim()).filter(Boolean);
      }),
    /** Where rate-limit counters live: shared across instances (postgres) or per process (memory). */
    RATE_LIMIT_STORE: z.enum(['postgres', 'memory']).default('postgres'),

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
    APNS_TOPIC: z.string().default('app.nameshake.ios'),

    APP_STORE_ISSUER_ID: optional,
    APP_STORE_KEY_ID: optional,
    APP_STORE_PRIVATE_KEY: pem,
    APP_STORE_APP_APPLE_ID: optional,
    APP_STORE_ENVIRONMENT: z.enum(['Production', 'Sandbox', 'Xcode', 'LocalTesting']).default('Sandbox'),

    PASS_TYPE_IDENTIFIER: z.string().default('pass.app.nameshake.ios.card'),
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

    /**
     * Log In with Telegram (OpenID Connect, https://core.telegram.org/bots/telegram-login): the bot's
     * Client ID and Secret from @BotFather → Login Widget. Register
     * `${API_BASE_URL}/v1/auth/telegram/callback` there as an Allowed URL. Empty → sign-in answers 503.
     */
    TELEGRAM_LOGIN_CLIENT_ID: optional,
    TELEGRAM_LOGIN_CLIENT_SECRET: optional,
    /** Telegram's OIDC issuer; tests point it at a local stand-in. */
    TELEGRAM_OIDC_ISSUER: z.url().default('https://oauth.telegram.org'),
    /** The app's URL scheme: the sign-in callback hands the authorization code back through it. */
    APP_URL_SCHEME: z.string().regex(/^[a-z][a-z0-9+.-]*$/).default('nameshake'),
    /** "Notify me" link for Android visitors on card pages (e.g. a waitlist form). Empty → hidden. */
    ANDROID_WAITLIST_URL: optional,

    APP_STORE_ID: optional,
    /** "Get the app" link before the App Store listing exists, e.g. the TestFlight public link. */
    APP_DOWNLOAD_URL: optional,

    /** Transactional mail (data export links). Empty → exports stay queued. */
    RESEND_API_KEY: optional,
    MAIL_FROM: z.string().default('Nameshake <no-reply@tanishly.app>'),
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
