# Metly API & Sync

Two audiences: **feature agents** (how to talk to the server from SwiftUI) and the **backend team**
(what the server must do). The wire contract is `openapi.yaml` next to this file; `MockMetlyServer`
(`Packages/MetlyKit/Sources/MetlyNetworking/Mock`) is an executable reference implementation of it.

---

## Using the API from features

### Rule 1 — plain data needs no API call
Profiles, cards, connections, follow-ups and events are **offline-first SwiftData records**. Mutate
the model, call `markChanged()` (or `markDeleted()` / `restore()`), done. The sync engine pushes
dirty records a moment later (debounced on `ModelContext.didSave`) and pulls everyone else's
changes. Never call `modelContext.delete(_:)` on synced models; never call REST endpoints for CRUD.

```swift
person.note = text
person.markChanged()          // synced automatically, also offline
reminder.markDeleted()        // tombstone → pushed → hard-deleted after the server confirms
```

Sync status for UI (skeletons, "Last synced"): `services.sync.status` (`.idle / .syncing / .offline /
.failed(message)`) and `services.sync.lastSyncedAt` — `AppServices.sync` is the `@Observable`
`SyncEngine`. Force a pass with `services.sync.requestSync()` (debounced) or `await services.sync.syncNow()`
(e.g. in `.refreshable`).

### Rule 2 — server-only actions go through `MetlyClient`
`MetlyClient` (`MetlyData`) is injected at the root and in every `metlyPreview(...)`:

```swift
import MetlyData
import MetlyNetworking

@Environment(MetlyClient.self) private var client
```

| Need | Call | Notes |
|---|---|---|
| Publish now (CARD_CREATE "Publish", Editor "Done") | `try await client.publish(card)` | Writes the server slug back to `card`. On error show ALERT_PUBLISH_FAILED — the card stays a draft and sync publishes it later. |
| Scanned Metly QR (SCANNED_CARD) | `try await client.publicProfile(slug:)` | `status != .available` → unavailable state. `.snapshot` feeds `CardFaceView`. `Brand.slug(from: url)` extracts the slug. |
| Wallet pass | `try await client.walletPass(for: card)` | `.pkpass` `Data` for `PKAddPassesViewController`. The mock throws `APIError.serverRequired("Wallet passes need the server.")` — show its `localizedDescription`. |
| Card stats | `try await client.refreshStats(for: card)` | Also stored on `card.stats`. |
| Connect: session & peers | `client.startConnectSession(cardID:eventID:method:)` → advertise `discoveryToken`; `client.resolvePeers(tokens:)` | In the simulator use `client.demoNearbyTokens` (mock people) since there are no MPC peers. |
| Connect: send + wait | `let r = try await client.sendConnectRequest(to: .nearbyToken(t), cardID:, method: .nearby)` then `switch await client.outcome(of: r)` | `.accepted(connectionID:)` → `router.replaceTop(with: .cover(.connected(connectionID:)))`; `.noResponse` → "{first} didn't respond…"; `.cancelled`. Cancelling the waiting task (closing Connect) returns `.cancelled`; call `await client.cancel(r)` to withdraw. |
| Accept / decline incoming | `try await client.accept(request, sharing: cardID)` → `Connection?` · `try await client.decline(request)` | Offline: queued (status set locally + `markChanged()`), `accept` returns `nil` and the connection arrives with the next sync. Setting `request.status = .accepted/.declined` + `markChanged()` yourself is equivalent — the sync engine turns it into `POST …/accept|decline`. |
| DEFERRED_WELCOME "Connect" | `try await client.connect(with: invite, sharing: cardID)` | Pre-approved; the connection arrives via realtime/sync. |
| People "Requests" refresh | `try await client.refreshIncomingRequests()` | Also happens on every sync. |
| Anything else | `client.api.<group>.<call>` | e.g. `client.api.events.eventSummary(id:)`, `client.api.profile.requestTelegramLink()`. |

### Realtime connect stream
Incoming requests, request results and web share-backs arrive on a WebSocket while signed in. The
records are **already saved to SwiftData** when an event arrives (so `@Query(ConnectRequest.pendingIncoming)`
updates by itself); listen only to react in UI:

```swift
.task {
    for await event in client.events() {          // independent stream per caller; ends with the view
        switch event {
        case .requestReceived(let request):        // INCOMING_REQUEST overlay while CONNECT is open
            incoming = request
        case .requestUpdated(let request, let connection):
            break                                   // outcome(of:) already handles your own request
        case .shareBackReceived(let notice):        // notice.connection.id, notice.mergeResult
            break
        case .syncAvailable, .stateChanged:
            break
        }
    }
}
```
`client.realtimeState` (`.connecting/.connected/.disconnected`) is observable. With the mock,
`client.mockServer?.simulateIncomingRequest()` and `simulateShareBack(name:phone:telegram:)` drive
these flows from DEBUG buttons/previews.

### Errors
Every call throws `APIError` (`MetlyNetworking`): `.offline`, `.timedOut`, `.unauthorized`,
`.rateLimited`, `.server(status:problem:)` (`error.code == .planLimitReached` etc.), `.serverRequired`.
`error.localizedDescription` is user-presentable. Client-side plan checks (`services.entitlements.limits`)
still come first; the server enforces the same limits as a backstop.

### Previews & simulator
- `#Preview { X().metlyPreview(.full, plan: .pro, online: false) }` injects a mock-backed `MetlyClient`
  (demo account, ~300 ms latency; `online: false` → every call throws `.offline`).
- App launch arguments (Debug): `-MetlyDemoData` (signed-in demo account; the mock mirrors it),
  `-MetlyMockExistingAccount` (empty device, signing in pulls the demo account),
  `-MetlyDeferredInvite` (DEFERRED_WELCOME with Kamila), `-MetlyUseMockServer` (ignore a configured URL),
  `-MetlyAPIBaseURL https://…` (override).
- Mock world: slugs `kamila-x1y2`, `sardor-r4t5`, `bekzod-b8n3` (accept after ~1.6 s),
  `nodira-n5m1` (never answers → `.noResponse` after ~8 s), `lola-p0z3` (paused). Nearby tokens
  `mock-peer-kamila|sardor|bekzod|nodira`.

### Backend selection
Info.plist `MetlyAPIBaseURL = $(METLY_API_BASE_URL)`. Empty or unresolved → `MockMetlyServer`
(seeded from the device store, so it agrees with whatever is on the device). Set the build setting
per configuration once the backend exists.

---

## For the backend team

### Accounts & sessions
- Sign in with Apple / Google only (no email/password, no magic link in v1). See `/v1/auth/*`.
- Access token: JWT (15–60 min). Refresh token: opaque, single-use, rotated on every refresh,
  60-day sliding expiry; reuse outside a 30 s grace window revokes the family. The client refreshes
  proactively and on `401`, one refresh at a time, and replays the failed request once.
- `401 invalid_grant` on refresh = signed out. Sign-out/delete wipe the device.
- Account deletion must also revoke the Apple token (`/auth/revoke`) — App Store requirement.

### Records, ids and timestamps
- Synced record types: `profile` (one per user), `card`, `event`, `connection`, `followUp`.
  `connectRequest` is server-driven (pulled, never pushed as a record).
- **Ids are generated on the device** (UUID v4) so records can be created offline. Treat writes as
  create-or-update by id (`PUT /…/{id}` and sync push). Never rewrite an id — exception: a second
  `profile` for the same user keeps the stored profile's id (returned as canonical; the app adopts it).
- `updatedAt` is set by the device on every user edit. `deletedAt` marks a tombstone.
- Server-owned fields are ignored on write and always returned: `profile.photoUrl/logoUrl`,
  `card.slug/url/publishState/isReadOnly/isPaused/stats`, `connection.avatarUrl`,
  `notificationPrefs.telegramLinked`.
- Store `updatedAt` with at least millisecond precision; return it unchanged.

### Sync protocol
```
device                                   server
  │ POST /v1/sync/push {changes}  ───────▶ apply each change with LWW, record a change sequence number
  │ ◀─────── {results[], records}          results: applied | stale | rejected (+error); records = canonical state
  │ GET /v1/sync?since=<cursor>   ───────▶ every record whose change seq > cursor (incl. tombstones)
  │ ◀─────── {changes, cursor, hasMore}    page until hasMore = false; store cursor after each page
```
1. **Push** (`POST /v1/sync/push`): all dirty records in one batch (≤ 500), upserts grouped by type plus
   `tombstones`. Process upserts in dependency order (profile → cards → events → connections →
   follow-ups), then tombstones children-first. Every change is independent: one invalid record never
   fails the batch. Return, for every applied or stale change, the canonical server record (or its
   tombstone) in `records` — the device uses it to learn slugs, stats, merges and conflicts.
2. **Pull** (`GET /v1/sync?since=&limit=`): keep a **per-user monotonic change sequence** (`seq`)
   bumped on every write (user or server-originated: merges, cascades, stats, auto-ended events,
   entitlement changes, share-backs). The cursor encodes the last `seq` delivered — never a
   timestamp (clock skew loses data). Return records with `seq > cursor` ordered by `seq`, `limit`
   per page, `hasMore` when more remain. `since` omitted = full snapshot (live records only).
3. Pushes produce changes too: they appear in the next pull (the device tolerates the echo). Using
   `deviceId` to suppress echoes is optional.
4. **Tombstones** live ≥ 90 days. A cursor older than the oldest kept tombstone (or unknown) →
   `410 cursor_expired`; the device then pulls a full snapshot and deletes synced local records that are
   not in it.
5. After every realtime (re)connect and on `sync.available` the device pulls. Emit `sync.available` to
   the user's other sockets whenever their data changes server-side.

### Conflict resolution (last write wins per record)
For an incoming upsert with `updatedAt = U` of record `id`:
- a tombstone exists with `deletedAt ≥ U` → **stale** (return the tombstone);
- a live record exists with `updatedAt > U` → **stale** (return the stored record);
- otherwise **applied**: store it (resurrecting a tombstoned id is allowed when `U > deletedAt`).

For an incoming tombstone with `deletedAt = D`: a live record with `updatedAt > D` → **stale** (return
it); otherwise delete, keep the tombstone, cascade (below) → **applied**.

The device applies pulled records with the same rule and never overwrites a record that has unsynced
local edits with older data. Field-level merging is not done (v1), except the documented merges below.

Cascades: deleting a connection tombstones its follow-ups; deleting an event clears `eventId` on its
connections (they keep `context.eventName`); renaming an event updates `context.eventName` of tagged
connections (their `updatedAt` = max(own, event's)).

### Uniqueness
- One live connection per (owner, `remoteUserId`). A pushed connection that duplicates another live
  one for the same Metly user is merged into the existing record (newer `updatedAt` wins, empty
  fields are filled), returned as canonical, and the pushed id is tombstoned (both in `records`).
  `POST /v1/connect/requests/{id}/accept` reuses that connection too. (The app creates a connection
  optimistically when accepting offline; this keeps it from duplicating.)
- Slugs are globally unique and never reused (deleted cards keep their slug retired).

### Slugs & publishing
- First accepted write of a card assigns `slug = {firstname}-{4}`: first name from `profile.fullName`,
  ASCII-folded, lowercase, `[a-z0-9]` only (fallback `card`); suffix from `abcdefghjkmnpqrstuvwxyz23456789`.
  Slugs are immutable in v1 (no custom slugs). URL: `https://metly.link/c/{slug}`.
- There are no server-side drafts: every accepted card is published. `publishState: draft` only exists
  on a device that hasn't synced the card yet.
- Pause: `profile.linksPaused` (global "Pause All Links") → every card `isPaused`, public pages show
  "This card isn't available right now." without personal data. Resume restores them (printed QR codes
  work again).
- Public surfaces (web page, `.vcf`, Wallet pass, `/api/public/*`) show **Public ∩ visibleFields** only.
  The authenticated `/v1/public-profiles/{slug}` adds **Connections** fields for connected viewers.
  **Private** fields never leave the owner's devices except in their own data export.

### Free limits (enforced server-side too)
| | Free | Pro |
|---|---|---|
| Cards | 2 (create/duplicate rejected beyond) | unlimited |
| Open follow-ups (`isDone == false`) | 5 (a write that would open a 6th is rejected) | unlimited |
| Active events | 1 | unlimited |
| Pro templates/palettes (`editorial`, `ocean`, `ember`) | rejected when a write changes the design to one | allowed |

Rejections: REST `403 plan_limit_reached` / `pro_required` (`details.limit`); sync push `status:
rejected` with the same error. The device does not retry a rejected record until it is edited again.
After a downgrade (App Store notification): cards beyond the 2 lowest `sortOrder` become
`isReadOnly` (still published); existing follow-ups/events above the limits stay, new ones are rejected.

### Share-back (web recipient → owner), SPEC §3.9–3.10
`POST /api/public/cards/{slug}/shareback` `{name, phone?, telegram?, metAt?, platform}` — name required
and phone **or** telegram. Then, for the card's owner, in this order:
1. **Dedupe**: a live connection with the same phone (digits only) or same Telegram handle
   (case-insensitive) → fill its missing phone/telegram silently, no new connection
   (`mergeResult: dedupedByPhoneOrTelegram`).
2. **New**: else create a connection: `fullName`, phone, telegram, `jobTitle: "Contact"`,
   `company: "Shared from your web page"`, `source: webShareBack`, `context.eventName` = owner's active
   event name else the sender's "Met at" text, `context.place` = active event place, `eventId` = active
   event (`created`). If a connection with `isPendingMerge == true` has the same first name
   (case-insensitive), put its id in `mergeCandidateId` — **do not merge it**: the app asks the owner
   "Is this the person you met at 14:32?" (PLAN Q18) and, on confirm, pushes an upsert of the just-met
   record (`isMerged = true`, phone/telegram filled) plus a tombstone of the share-back connection.
Then: bump the connection's `seq`, increment the card's `stats.shareBacks`, send realtime
`shareback.received` + PUSH_SHAREBACK ("{first} shared their contact with you" / "{event}" or
"From your web page"), return `{shareBackId, removalToken}`. Blocked senders and paused cards: respond
`201` but store nothing. "Remove my contact" (`DELETE /api/public/sharebacks/{id}` + token) removes
exactly what the share-back added (tombstone if it created the connection).

### Connect requests
- Live (`nearby`, `tapPhones`): `expiresAt = now + 60 s`. Async (`scan`, `emailLookup`): 7 days.
  `deferred`: accepted immediately (the owner shared their card with the installer).
- Accept creates/updates a connection on **both** sides (see openapi `acceptConnectRequest`), notifies
  the requester (`connect.request.updated` with their connection) and adds both to each other's sync.
- Decline is silent: the requester's request stays `pending` until `expiresAt`, then becomes `expired`
  (they see "didn't respond", never "declined").
- Requests from/to blocked users are dropped silently; hidden users (`showInNearby = false`) never
  resolve via `/v1/connect/peers`.

### Push notifications (APNs, token auth .p8)
Types: `connect_request`, `connect_result`, `shareback_received`, `card_saved`, `followup_due`,
`event_summary`, `weekly_summary`, `product_news`, each gated by the matching `notificationPrefs`
toggle. Payload carries `type` and ids (`connectionId`, `requestId`, `followUpId`, `eventId`) for
deep links. Follow-up reminders: category `FOLLOWUP` with actions "Open Telegram" / "Snooze 1 Day",
`apns-collapse-id = followUpId` (the app also schedules a local notification as an offline fallback).
Lock-screen privacy: no note text in pushes.

### Other server jobs
- Auto-end active events after `endDate` (owner's time zone) + PUSH_EVENT_SUMMARY.
- Reminder scheduler (APNs or Telegram bot per `notificationPrefs.delivery`).
- Wallet pass updates via the PassKit web service whenever a card's public content changes.
- Stats aggregation (views dedupe 30 min, `?src=qr` = scan).
- App Store Server Notifications V2 → entitlements, read-only cards, `sync.available`.
- Data export ZIP (JSON + CSV + images) emailed within 24 h.

### Rate limits & abuse
See openapi `info.description`. Public endpoints need IP limits, bot filtering and a honeypot on
share-back; consider Cloudflare Turnstile (`captchaToken`) if spam appears.

### Open backend questions
- Email-change / provider linking (Apple + Google on one account) — out of v1.
- Analytics opt-in endpoint (`shareAnalytics`) — not specified yet.
- Exact pass design and Pass Type ID (`pass.com.metly.app.card` proposed).
