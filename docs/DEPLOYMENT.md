# Deploying Nameshake

The API is one Docker image (`backend/Dockerfile`) plus a PostgreSQL database. It runs on any host
that runs containers. Everything optional (push, Wallet, uploads, subscriptions, Google/Telegram sign-in, mail) is
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
  Uzbekistan to be stored on servers located in Uzbekistan. If Nameshake targets users there, host the
  database (and the API) in a local data centre or get legal advice before launch. The image is
  host-agnostic, so this is a deployment choice, not a code change.

The API scales horizontally: rate-limit counters live in Postgres (`RATE_LIMIT_STORE=postgres`, the
default), realtime fan-out uses Postgres LISTEN/NOTIFY and scheduled jobs take advisory locks. Set
`TRUST_PROXY` to the number of proxies in front of the API (1 on Render/Railway/Fly) so rate limits see
the real client IP.

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
| `TRUST_PROXY` | proxy hops in front of the API (`1` behind one load balancer); never `true` |
| `RATE_LIMIT_STORE` | `postgres` (default; shared by all instances) |
| `APPLE_BUNDLE_IDS` | `app.nameshake.ios` |
| `APPLE_TEAM_ID`, `APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY` | Sign in with Apple key (.p8) — needed to revoke tokens on account deletion (App Store rule) |
| `GOOGLE_CLIENT_IDS` | iOS OAuth client id from Google Cloud Console (see § 6) |
| `TELEGRAM_LOGIN_CLIENT_ID`, `TELEGRAM_LOGIN_CLIENT_SECRET` | Log In with Telegram (see § 7) |
| `APP_URL_SCHEME` | the app's URL scheme (`nameshake`); Telegram sign-in returns to the app through it |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC` | APNs auth key (.p8); topic `app.nameshake.ios` |
| `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, `APP_STORE_PRIVATE_KEY`, `APP_STORE_APP_APPLE_ID`, `APP_STORE_ENVIRONMENT` | App Store Server API key; `Production` after release |
| `PASS_TYPE_IDENTIFIER`, `PASS_TEAM_ID`, `PASS_CERT_PEM`, `PASS_KEY_PEM`, `PASS_KEY_PASSPHRASE`, `PASS_WWDR_PEM` | Wallet pass certificate + Apple WWDR G4 |
| `S3_*` | Cloudflare R2 (or S3) bucket for photos/logos; `S3_PUBLIC_BASE_URL` = the public bucket/CDN URL |
| `ANDROID_WAITLIST_URL` | optional "Notify me" link for Android visitors on card pages |
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

1. Identifiers: App ID `app.nameshake.ios` (Sign in with Apple, Push, Associated Domains, App Groups,
   Wallet), `app.nameshake.ios.widgets`, App Group `group.app.nameshake.ios`, Pass Type ID
   `pass.app.nameshake.ios.card`.
2. Keys: Sign in with Apple key, APNs key (can be one key with both), App Store Server API key.
3. App Store Connect: app record, subscriptions `app.nameshake.ios.pro.monthly` and
   `app.nameshake.ios.pro.yearly` in one group, App Store Server Notifications V2 URL
   `https://api.tanishly.app/v1/webhooks/app-store` (production and sandbox).
4. Xcode Release configuration: `DEVELOPMENT_TEAM`, `METLY_API_BASE_URL=https://api.tanishly.app`
   (the Release build fails without it, by design), `GOOGLE_CLIENT_ID`.

## 6. Sign in with Google

1. Google Cloud Console → APIs & Services → OAuth consent screen: app name **Nameshake**, support
   email, privacy policy `https://tanishly.app/privacy`, scopes `openid`, `email`, `profile`.
2. Credentials → Create OAuth client ID → **iOS**, bundle ID `app.nameshake.ios`. Copy the client ID
   (`…apps.googleusercontent.com`; not a secret).
3. Xcode build setting `GOOGLE_CLIENT_ID` (both configurations) = that client ID. The app derives the
   reversed-client-ID callback scheme from it; no SDK and no Info.plist URL type are needed because
   `ASWebAuthenticationSession` receives the redirect.
4. Backend `GOOGLE_CLIENT_IDS` = the same client ID (comma-separate a second one for a debug bundle).

## 7. Log In with Telegram

1. In @BotFather create (or pick) the bot users will see on the consent screen — name and photo should
   be Nameshake's.
2. @BotFather → the bot → **Login Widget**: add the Allowed URL
   `https://api.tanishly.app/v1/auth/telegram/callback` (and your staging API's callback). Copy the
   **Client ID** and **Client Secret**.
3. Backend: `TELEGRAM_LOGIN_CLIENT_ID`, `TELEGRAM_LOGIN_CLIENT_SECRET`. Keep `APP_URL_SCHEME` equal to
   the app's URL scheme (`nameshake`). The app needs no Telegram settings: it starts at the API.
4. Check: `curl -I "https://api.tanishly.app/v1/auth/telegram/authorize?code_challenge=$(printf %043d 0)&state=0123456789abcdef&nonce=0123456789abcdef"`
   answers `302` to `oauth.telegram.org` (a redirect to `nameshake://auth/telegram?error=temporarily_unavailable`
   means the client id/secret are missing).

