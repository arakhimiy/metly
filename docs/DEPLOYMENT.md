# Deploying Tanishly

The API is one Docker image (`backend/Dockerfile`) plus a PostgreSQL database. It runs on any host
that runs containers. Everything optional (push, Wallet, uploads, subscriptions, Telegram, mail) is
switched on by setting its environment variables; until then those endpoints answer
`503 service_unavailable` and the rest works.

## 1. What has to exist before the first public build

| Item | Why | Notes |
|---|---|---|
| Domain `tanishly.app` | Printed QR codes encode `https://tanishly.app/c/{slug}` — it can never change afterwards | Registrar of choice; DNS can stay with the registrar or move to Cloudflare |
| `api.tanishly.app` | The app's `METLY_API_BASE_URL` | CNAME/A to the API host |
| `tanishly.app/c/*` and `/.well-known/apple-app-site-association` | Web card page + Universal Links | Served by the same API (point the apex at it, or proxy those paths) |
| Privacy Policy, Terms, Support pages | App Store requires a privacy policy URL; the app links `tanishly.app/privacy`, `/terms`, `/help` | Any static host |
| `support@tanishly.app` | Shown in the app and App Store listing | Email forwarding at the registrar is enough |
| Apple Developer Program team | App Store, TestFlight, Push, Sign in with Apple, Wallet, Associated Domains | The team that owns the app also owns users' Sign in with Apple identifiers — pick the final team before launch (moving later needs a user-migration) |

## 2. Hosting

Requirements: containers, managed PostgreSQL 16+ with daily backups, HTTPS, WebSocket support
(`/v1/realtime`), and `X-Forwarded-For` from the load balancer.

- **Testing / TestFlight (free or near-free):** Render or Railway for the container + Neon for
  PostgreSQL. Expect cold starts on free tiers.
- **Production:** a small always-on instance (1 vCPU, 1 GB) and managed PostgreSQL with backups is
  plenty for the first tens of thousands of users.
- **Uzbekistan data localisation:** the Law on Personal Data requires personal data of citizens of
  Uzbekistan to be stored on servers located in Uzbekistan. If Tanishly targets users there, host the
  database (and the API) in a local data centre or get legal advice before launch. The image is
  host-agnostic, so this is a deployment choice, not a code change.

One instance is enough to start. Before running several instances, move the in-memory rate-limit
counters to Redis or Postgres (`src/common/rate-limit.ts`); realtime fan-out and scheduled jobs are
already safe across instances (Postgres LISTEN/NOTIFY and advisory locks).

## 3. Environment

Copy `backend/.env.example`; production refuses to boot when `JWT_SECRET` is the example,
`DEV_AUTH_ENABLED=true`, URLs are not https, or `APPLE_BUNDLE_IDS` is empty.

| Variable | Value |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | managed PostgreSQL URL (with `sslmode=require` if the provider needs it) |
| `WEB_BASE_URL` | `https://tanishly.app` (never change after launch) |
| `API_BASE_URL` | `https://api.tanishly.app` |
| `JWT_SECRET` | `openssl rand -base64 48` |
| `APPLE_BUNDLE_IDS` | `app.tanishly.ios` |
| `APPLE_TEAM_ID`, `APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY` | Sign in with Apple key (.p8) — needed to revoke tokens on account deletion (App Store rule) |
| `GOOGLE_CLIENT_IDS` | iOS OAuth client id from Google Cloud Console |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC` | APNs auth key (.p8); topic `app.tanishly.ios` |
| `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, `APP_STORE_PRIVATE_KEY`, `APP_STORE_APP_APPLE_ID`, `APP_STORE_ENVIRONMENT` | App Store Server API key; `Production` after release |
| `PASS_TYPE_IDENTIFIER`, `PASS_TEAM_ID`, `PASS_CERT_PEM`, `PASS_KEY_PEM`, `PASS_KEY_PASSPHRASE`, `PASS_WWDR_PEM` | Wallet pass certificate + Apple WWDR G4 |
| `S3_*` | Cloudflare R2 (or S3) bucket for photos/logos; `S3_PUBLIC_BASE_URL` = the public bucket/CDN URL |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_WEBHOOK_SECRET` | @TanishlyBot; set the bot webhook to `https://api.tanishly.app/v1/integrations/telegram/webhook` with that secret |
| `RESEND_API_KEY`, `MAIL_FROM` | data-export emails |
| `APP_STORE_ID` | numeric App Store id, after the listing exists (Smart App Banner, "Get the app") |
| `APP_DOWNLOAD_URL` | before the listing exists: TestFlight public link for "Get the app" (hidden on Android, no Smart App Banner) |

Multi-line keys can be stored with literal `\n`; the app restores newlines.

## 4. Release steps

```bash
docker build -t metly-api backend
docker run --env-file backend/.env -p 3000:3000 metly-api   # applies migrations, then serves
curl https://api.tanishly.app/health/ready
```

The container runs `prisma migrate deploy` before starting, so a deploy is: build, push, restart.
Migrations are additive; roll back by deploying the previous image (do not roll back migrations).

## 5. Apple configuration checklist

1. Identifiers: App ID `app.tanishly.ios` (Sign in with Apple, Push, Associated Domains, App Groups,
   Wallet), `app.tanishly.ios.widgets`, App Group `group.app.tanishly.ios`, Pass Type ID
   `pass.app.tanishly.ios.card`.
2. Keys: Sign in with Apple key, APNs key (can be one key with both), App Store Server API key.
3. App Store Connect: app record, subscriptions `app.tanishly.ios.pro.monthly` and
   `app.tanishly.ios.pro.yearly` in one group, App Store Server Notifications V2 URL
   `https://api.tanishly.app/v1/webhooks/app-store` (production and sandbox).
4. Xcode Release configuration: `DEVELOPMENT_TEAM`, `METLY_API_BASE_URL=https://api.tanishly.app`
   (the Release build fails without it, by design), `GOOGLE_CLIENT_ID`.
