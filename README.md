# Nameshake

Digital business cards for iPhone: share your card by QR code, nearby connect or a link, save the
people you meet with where and why you met, and get reminded to follow up. Offline-first, with a
NestJS backend for sync, public card pages, Apple Wallet passes and subscriptions.

| Part | Stack | Where |
|---|---|---|
| iOS app + widgets | SwiftUI, Swift 6, SwiftData, iOS 18+, no third-party dependencies | `Metly/`, `MetlyWidgets/`, `Packages/MetlyKit/` |
| API | NestJS 12, TypeScript 6, PostgreSQL (Prisma 7), Node 24 | `backend/` |
| Contract | OpenAPI 3.1 + sync protocol | `docs/api/openapi.yaml`, `docs/api/README.md` |
| Product spec | Screens, flows, copy | `prd/SPEC.md` (prototype: `prd/Cardy App v8.dc.html`) |

## Names in this repo

The product is **Nameshake**. Two older names remain on purpose:

- **Metly** is the codebase name: the Xcode project and scheme, the `Metly*` / `Feature*` Swift
  modules, Info.plist keys (`MetlyAPIBaseURL`…). Renaming them is churn with no user-visible effect.
- **nameshake** is in the app identifiers: bundle id `app.nameshake.ios` (widgets `.widgets`), App Group
  `group.app.nameshake.ios`, Pass Type ID `pass.app.nameshake.ios.card`, in-app purchase ids, the
  `nameshake://` URL scheme and the npm package name (renamed from `tanishly` on 2026-11-13).
- **tanishly.app** is still the web/API domain placeholder (`WEB_BASE_URL`, `API_BASE_URL`, support email)
  until the Nameshake domain is bought; it must be final before the first public build, because printed
  QR codes encode it (see `docs/DEPLOYMENT.md`).

## Quick start

Requirements: macOS with Xcode 27, Node 24 (`backend/.nvmrc`). No Docker needed.

### Backend

```bash
cd backend
npm ci                      # installs and generates the Prisma client
cp .env.example .env        # set JWT_SECRET: openssl rand -base64 48
npm run db:start            # embedded PostgreSQL on :54329 — leave it running in its own terminal
npm run db:deploy           # apply migrations
npm run build && npm start  # http://localhost:3000, health: /health/ready
```

`DEV_AUTH_ENABLED=true` (the `.env.example` default) enables `POST /v1/auth/dev`, so you can sign in
without Apple, Google or Telegram. More in [`backend/README.md`](backend/README.md).

### iOS app

```bash
scripts/run.sh --local      # build, install and launch in the simulator against localhost:3000
scripts/run.sh --mock       # …or against the in-app mock server, no backend at all
scripts/run.sh --demo       # …signed in with demo data
```

Or open `Metly.xcodeproj` and run the **Metly** scheme (⌘R). In Debug builds the sign-in screen has
**Sign in as a test user**, which uses the backend's dev sign-in. Sign in with Apple needs a device
signed with the team's profile; Google and Telegram need their client IDs (see
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) §§ 6–7).

`scripts/build.sh` builds without signing, so it is for compile checks and tests, not for running:

```bash
scripts/build.sh app                 # app + widgets
scripts/build.sh FeaturePeople       # one module
scripts/build.sh FeaturePeople test  # one module's tests
scripts/build.sh all test            # every MetlyKit test target (what CI runs)
```

## Tests and CI

| | Command | CI |
|---|---|---|
| Backend | `cd backend && npm run typecheck && npm test` (unit + e2e; e2e starts its own PostgreSQL and checks every response against the OpenAPI schemas) | `.github/workflows/backend.yml` |
| iOS | `scripts/build.sh app` and `scripts/build.sh all test` | `.github/workflows/ios.yml` (GitHub `xcode-27` runner) |

## Documentation

- [`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md) — iOS architecture, module rules, HIG rules, Swift rules.
- [`docs/api/README.md`](docs/api/README.md) — sync protocol, conflict rules, push, limits.
- [`backend/README.md`](backend/README.md) — backend architecture and the rules that keep sync correct.
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — hosting, environment, Apple / Google / Telegram setup.
- [`docs/PLAN.md`](docs/PLAN.md) — product decisions.
