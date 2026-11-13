# Nameshake API

NestJS 12 · TypeScript 6 · PostgreSQL (Prisma 7) · Node 24. Implements `../docs/api/openapi.yaml`
(wire contract) and `../docs/api/README.md` (sync protocol, conflict rules, share-back, Free limits).
The iOS mock server (`../Packages/MetlyKit/Sources/MetlyNetworking/Mock/`) is an executable reference
of the same behaviour — when the docs are silent, match it.

## Run locally

```bash
npm ci                    # also generates the Prisma client (postinstall); after editing
                          # prisma/schema.prisma run `npm run db:generate`
cp .env.example .env
npm run db:start          # embedded PostgreSQL on :54329 (no Docker needed); leave it running
npm run db:deploy         # apply migrations
npm run build && npm start
```

`POST /v1/auth/dev {"subject":"me","fullName":"Kamola"}` signs in without Apple/Google/Telegram while
`DEV_AUTH_ENABLED=true` (refused in production).

## Tests

```bash
npm run typecheck
npm test                  # unit + e2e; e2e starts its own throwaway PostgreSQL
npx vitest run --project e2e test/sync.e2e.ts
```

E2E tests drive the real HTTP stack and validate every response body against the OpenAPI schemas
(`test/contract.ts` → `expectSchema('Card', body)`). Do not run `npm run build` while a server from
`dist/` is running — it deletes `dist/`.

## Architecture

```
src/
  config/        env.ts — every setting, validated at boot (production refuses unsafe values)
  common/        ApiError + global filter (openapi Error body), zod `parse`, rate limits (Postgres-shared),
                 Idempotency-Key interceptor, cursors, DomainEvents (after-commit hooks)
  prisma/        PrismaService: nextSeq (per-user change counter), lockUsers, write (transaction)
  auth/          Apple / Google / Telegram (OIDC + PKCE) / dev sign-in, JWT access + rotating refresh
                 tokens, global AuthGuard
  records/       Profile, cards, events, connections, follow-ups: RecordsService is the facade over
                 writers/* (one per record type: LWW, limits, slugs, merges, cascades) shared by REST
                 controllers and sync; write-context.ts (transaction + effects); wire schemas + mappers
  sync/          POST /v1/sync/push, GET /v1/sync
  realtime/      WebSocket /v1/realtime; fan-out through Postgres LISTEN/NOTIFY
  account/       /v1/me, account deletion, export request
  subscriptions/ EntitlementsService (plan + limits)
  push/          PushService.notify(userId, message) — frozen API; text rendered per device language
  i18n/          uz / ru / en: Lang, langFromLocale, pickLang, plural; push catalog
                 (messages.ts), card page texts (web-page.ts)
  connect/       connect sessions, peers, requests, blocks, public profiles
  web/           tanishly.app pages, vCard, public JSON, share-back, web analytics, AASA, deferred links
  platform/      devices + APNs, jobs, App Store subscriptions
  media/         uploads (S3), Apple Wallet + PassKit web service, data export
```

### Rules that keep sync correct

- **Every write to a synced record bumps the owner's seq** (`prisma.nextSeq(tx, userId)`) and stores
  it on the row; that is what `GET /v1/sync` pages by. Writes go through `RecordsService.write(userId,
  ctx => …)` so side effects (`user.changed` → realtime `sync.available`, `cards.content.changed` →
  Wallet updates) are published after commit.
- A transaction that writes records of **two users** calls `prisma.lockUsers(tx, [a, b])` first.
- Tombstones are rows with `deletedAt`; never hard-delete a synced record (the purge job does that
  after 90 days and raises `users.tombstone_floor_seq`).
- Connect requests carry a seq per side (`fromSeq`, `toSeq`) and appear in both users' pulls.
  `ConnectRequestView` renders one request per viewer (the requester never sees "declined").
- Privacy: public surfaces show `Public ∩ visibleFields`; Connections fields only for an accepted,
  mutual connect (`connections.is_mutual`); Private never leaves the owner (`records/snapshot.ts`).
- Responses never contain empty-string URLs (Swift `URL` decoding rejects them) — omit instead.
- Fields added after v1 (labelled phones: `phoneLabel`, `additionalPhones`) are optional on write: an
  absent key parses to `undefined`, so Prisma keeps the stored value on update and the column default on
  create — older app builds never wipe them. Phone visibility/merging lives in `records/phones.ts`.

### Rate limits and client IPs

Budgets live in `common/rate-limit.ts` (mirrors openapi § Rate limits). Counters are fixed windows in
the UNLOGGED `rate_limit_windows` table, so every instance shares them (`RATE_LIMIT_STORE=memory` keeps
them per process). The client IP comes from `X-Forwarded-For` only as far as `TRUST_PROXY` allows
(default one hop: the platform's load balancer); `"true"` is refused because any client could then
choose its own IP.

### Log In with Telegram

`auth/telegram.service.ts`, OIDC Authorization Code + PKCE (https://core.telegram.org/bots/telegram-login):
the app opens `GET /v1/auth/telegram/authorize` in `ASWebAuthenticationSession` → Telegram →
`GET /v1/auth/telegram/callback` (the redirect URI registered with @BotFather) → `{APP_URL_SCHEME}://auth/telegram?code&state`
→ the app posts `code` + PKCE verifier + nonce to `POST /v1/auth/telegram`; the server redeems the code
with the client secret and verifies the id_token against Telegram's JWKS. `test/telegram-login.e2e.ts`
runs the whole flow against a local stand-in for oauth.telegram.org.

### Background jobs

Every job takes a Postgres advisory lock (one instance runs it), is off under `NODE_ENV=test`, and has
a `runOnce()` the tests call directly: follow-up reminders and event auto-end (every minute), connect
request expiry (10 s), lapsed entitlements (10 min), data export (5 min), abandoned uploads (hourly),
purge of 90-day-old tombstones and housekeeping tables (daily; raises `tombstone_floor_seq`).

### Languages (uz, ru, en)

Server-made texts — push notifications and the card web pages — come from
`src/i18n/`; API error messages stay English (developer-facing; the app shows its own texts).

- **Push**: callers pass a catalog id + parameters (`text: { id: 'followUpDue', params: {...} }`);
  `PushService` renders it once per language and sends each device the text in its own
  `devices.locale`: `uz*` → uz, `ru*` → ru, any other language → en (iOS always sends a locale, so
  that person reads neither Uzbek nor Russian), no locale → uz.
- **Web pages**: `?lang=` → `Accept-Language` → uz (`pickLang`), `<html lang>`, `Vary: Accept-Language`.
  The page script's texts arrive as JSON in `<body data-t>`, so the nonce'd script stays constant.
- Russian texts never decline a person's name or put it next to a gendered past-tense verb; counted
  nouns use `plural(lang, n, forms)` (Russian one/few/many; Uzbek nouns stay singular).

### Test doubles

Under `NODE_ENV=test` nothing leaves the process: pushes land in `pushTestSink`
(`src/push/push-test-sink.ts`), Wallet pass pushes in `TestPassPushSink`, and with
`METLY_TEST_STORAGE=memory` object storage is in memory.

### Errors

Throw `ApiError` (`common/api-error.ts`). Validation: `parse(schema, body)` → 422 with field details.
5xx bodies are generic; details go to the log.

## Deploy

`docker build -t metly-api backend` (or `docker compose up --build` in `backend/` for a local stack
with PostgreSQL). The container runs `prisma migrate deploy`, then `node dist/main.js`. Health:
`GET /health/live`, `GET /health/ready`. Hosting, environment and Apple setup: `../docs/DEPLOYMENT.md`.
