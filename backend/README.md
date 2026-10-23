# Metly API

NestJS 12 · TypeScript 6 · PostgreSQL (Prisma 7) · Node 24. Implements `../docs/api/openapi.yaml`
(wire contract) and `../docs/api/README.md` (sync protocol, conflict rules, share-back, Free limits).
The iOS mock server (`../Packages/MetlyKit/Sources/MetlyNetworking/Mock/`) is an executable reference
of the same behaviour — when the docs are silent, match it.

## Run locally

```bash
npm ci
cp .env.example .env
npm run db:start          # embedded PostgreSQL on :54329 (no Docker needed); leave it running
npm run db:deploy         # apply migrations
npm run build && npm start
```

`POST /v1/auth/dev {"subject":"me","fullName":"Kamola"}` signs in without Apple/Google while
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
  common/        ApiError + global filter (openapi Error body), zod `parse`, rate limits,
                 Idempotency-Key interceptor, cursors, DomainEvents (after-commit hooks)
  prisma/        PrismaService: nextSeq (per-user change counter), lockUsers, write (transaction)
  auth/          Apple / Google / dev sign-in, JWT access + rotating refresh tokens, global AuthGuard
  records/       Profile, cards, events, connections, follow-ups: RecordsService (LWW, limits, slugs,
                 merges, cascades) shared by REST controllers and sync; wire schemas + mappers
  sync/          POST /v1/sync/push, GET /v1/sync
  realtime/      WebSocket /v1/realtime; fan-out through Postgres LISTEN/NOTIFY
  account/       /v1/me, account deletion, export request
  subscriptions/ EntitlementsService (plan + limits)
  push/          PushService.notify(userId, message) — frozen API
  connect/       connect sessions, peers, requests, blocks, public profiles
  web/           metly.link pages, vCard, public JSON, share-back, web analytics, AASA, deferred links
  platform/      devices + APNs, jobs, Telegram, App Store subscriptions
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

### Background jobs

Every job takes a Postgres advisory lock (one instance runs it), is off under `NODE_ENV=test`, and has
a `runOnce()` the tests call directly: follow-up reminders and event auto-end (every minute), connect
request expiry (10 s), lapsed entitlements (10 min), data export (5 min), abandoned uploads (hourly),
purge of 90-day-old tombstones and housekeeping tables (daily; raises `tombstone_floor_seq`).

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
