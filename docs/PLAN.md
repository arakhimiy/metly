# Metly iOS — Implementation Plan

Source of truth for product behaviour: `prd/SPEC.md` (screen IDs, flows, data model).
Visual source of truth: **Apple Human Interface Guidelines** — the HTML prototype is NOT a visual reference.

## Decisions (confirmed with product owner)

| Topic | Decision |
|---|---|
| Name / bundle | **Metly** · `com.metly.app` · widgets `com.metly.app.widgets` · App Group `group.com.metly.app` |
| Public links | `https://metly.link/c/{slug}` · Telegram bot `@MetlyRemindBot` · support `support@metly.link` |
| Min iOS | **iOS 18.0** (built with Xcode 26 / iOS 26 SDK). Liquid Glass only behind `if #available(iOS 26, *)` with material fallbacks. |
| UI | 100% native SwiftUI + HIG: system components, SF Symbols, semantic colors, Dynamic Type, Dark/Light (follows system + in-app override), VoiceOver. Accent = teal (`AccentColor`). |
| Data | **Offline-first**: SwiftData is the local source of truth; a sync engine pushes dirty records to the backend and pulls deltas. |
| Backend | Not built yet. We author the contract (`docs/api/openapi.yaml`); app ships with `MockMetlyServer` until the real base URL exists. |
| Auth | **Sign in with Apple** + **Google** (native ASWebAuthenticationSession + PKCE OAuth — zero third-party dependencies). No email magic link. |
| Language | English only, via String Catalogs (ready for more locales). |
| v1 scope IN | Cards (9 templates), QR (online + offline vCard), share/export (PNG/PDF/Lock Screen), **Apple Wallet pass**, Scan (QR + paper OCR), Connect (Nearby/Tap), People + context + voice notes, Follow-ups + notifications, Events (+ CSV export), Profile/Settings, Paywall (StoreKit 2), **Widgets + App Intents**. |
| v1 scope OUT | All AI features (AI card designs, recap, briefing), CRM integrations (HubSpot/amoCRM/Bitrix24/Sheets) — CSV export only, email sign-in. Hide those entry points entirely (no "coming soon" stubs). |

## Resolved open questions from SPEC §9 (engineering defaults)

- Q4 privacy: every surface that can leave the device (web page, exports, Wallet, widgets on Lock Screen) shows **Public** fields only; in-app card previews show Public + Connections. Private never appears on a card.
- Q5 pause: single global "Pause All Links" (Profile) — Share sheet toggle mirrors it.
- Q7 Connect: **MultipeerConnectivity** for Nearby discovery/token exchange; **NearbyInteraction** distance (≤10 cm) for Tap Phones on UWB devices, fallback to MPC + "bump" confirmation on non-UWB.
- Q8/Q11: every in-app connect is a request the other side accepts; accepting always lands on CONNECTED (context capture).
- Q9: decliner is not notified → requester sees "No response" (never "declined").
- Q12: Editor works on a draft copy; Cancel discards, Done saves + publishes (queued offline).
- Q13: Free limit (5 open follow-ups) enforced everywhere; one open follow-up per person from capture flows.
- Q16/Q17: Location (When In Use) for place auto-fill, Calendar (full access read) for event suggestions, Speech (on-device) for voice notes — all requested **in context**, not in onboarding.
- Q18: share-back merge with a "just met" record requires an explicit confirmation row ("Is this the person you met at 14:32?").
- Q23: Lock Screen widget renders the QR itself; Control Center control + App Shortcut "Show My QR" open QR_FULLSCREEN.
- Q27: cancel/change subscription → `manageSubscriptionsSheet`.
- Q28: Appearance = System / Light / Dark (default System).
- Q32: tab bar stays visible on pushed screens (iOS convention); hidden only under covers.
- Q33: custom share sheet (card header + Copy Link + Wallet + Export + Pause) whose "More…" opens the system `ShareLink`.
- Q36: single account, multi-device via server sync; last-write-wins by `updatedAt` per record.
- Q40: action labels capitalised ("Message", "Call", "Mail", "Save").
- Q46: sign-out wipes the local store and Keychain.

## Architecture (short — details in `docs/ARCHITECTURE.md`)

- `Metly.xcodeproj` — thin **app target** (`Metly/`) + **widget extension** (`MetlyWidgets/`), both file-system-synchronized folders (adding files never edits `project.pbxproj`).
- `Packages/MetlyKit` — local Swift package, one module per area. Features never import other features; they navigate through `AppRouter` + route enums in `MetlyCore`. The app target's `RouteResolver` is the only place that knows every feature.

```
MetlyCore      routes/router, domain enums & value types, service protocols, env, utils
MetlyDesign    HIG components, toast/undo HUD, avatars, field icons, glass helpers, haptics
MetlyCardKit   CardFace renderer (9 templates × 6 palettes × light/dark), QR, vCard, exports
MetlyData      SwiftData schema, preview/seed data, sync engine, repositories
MetlyNetworking API client, DTOs, endpoints, MockMetlyServer, Keychain session store
MetlyCapture   shared context-capture block (where/note/voice/tags/follow-up), Contacts saver, location
Feature*       one per area (see ownership table)
```

## Work breakdown & ownership (no two agents ever own the same path)

| # | Agent | Owns (exclusive write access) | Screens (SPEC IDs) | Wave |
|---|---|---|---|---|
| 0 | **Orchestrator (me)** | `Metly.xcodeproj`, `Metly/` (except `Metly/AppIntents/`), `Packages/MetlyKit/Package.swift`, `Sources/MetlyCore`, `docs/`, `scripts/` | app shell, router, tab bar, RouteResolver | 0 + integration |
| 1 | CardKit | `Sources/MetlyCardKit`, `Tests/MetlyCardKitTests` | Appendix B, QR, vCard, PNG/PDF/Lock renderers | 1 |
| 2 | Data & Sync | `Sources/MetlyData`, `Sources/MetlyNetworking`, their tests, `docs/api/openapi.yaml` | sync, auth session, mock server | 1 |
| 3 | Onboarding & Auth | `Sources/FeatureOnboarding` + tests | ONB_WELCOME, AUTH_SIGNUP, SETUP_PROFILE, SETUP_PERMISSIONS, DEFERRED_WELCOME | 1 |
| 4 | People & Context | `Sources/FeaturePeople`, `Sources/MetlyCapture` (shared capture block) + tests | PEOPLE, CONNECTION_DETAIL, ADD_CONTEXT, JUST_MET, context capture + voice note, blocked people | 1 |
| 5 | Profile & Paywall | `Sources/FeatureProfile` + tests, `Metly/Metly.storekit` | PROFILE, SETTINGS_*, PAYWALL | 1 |
| 6 | Cards & Sharing | `Sources/FeatureCards` + tests | CARD_CREATE, CARD_EDITOR, CARD_SETTINGS, CARD_EXPORT, QR_FULLSCREEN, SHARE_SHEET, card menus | 2 |
| 7 | Scan | `Sources/FeatureScan` + tests | SCAN, SCANNED_CARD, PAPER_REVIEW | 2 |
| 8 | Connect | `Sources/FeatureConnect` + tests | CONNECT, INCOMING_REQUEST, CONNECTED | 2 |
| 9 | Home & Follow-ups | `Sources/FeatureHome` + tests | HOME, FOLLOWUPS, REMINDER_EDIT, notification categories & local scheduling | 2 |
| 10 | Events | `Sources/FeatureEvents` + tests | START_EVENT, EVENT_DETAIL, EVENT_ENDED, EVENT_EXPORT (CSV) | 2 |
| 11 | Widgets & Intents | `MetlyWidgets/`, `Metly/AppIntents/`, `Sources/MetlyWidgetKit` | WIDGET_*, App Shortcuts, Control | 3 |

`MetlyDesign` is written by me in wave 0; agents that need a new shared component put it **inside their own module** and list it in their report — I promote it to `MetlyDesign` during integration.

## Phases

**Wave 0 — Foundation (orchestrator, sequential).** git repo, Xcode project (2 targets, entitlements, Info.plist, scheme + StoreKit config), package with every module stubbed, frozen contracts: SwiftData schema + seed data, route enums + `AppRouter`, service protocols, `CardFaceView` public API stub, design components, `RouteResolver` wired to placeholder feature roots. Must build and launch before any agent starts.

**Wave 1 (5 agents in parallel, isolated git worktrees):** CardKit · Data & Sync · Onboarding & Auth · People & Context · Profile & Paywall.
→ Orchestrator merges branches, builds, runs on simulator, fixes integration, promotes shared components.

**Wave 2 (5 agents):** Cards & Sharing · Scan · Connect · Home & Follow-ups · Events (they now build on real CardKit + Data).
→ Merge, integrate, simulator pass.

**Wave 3:** Widgets & Intents agent; orchestrator does full HIG / accessibility / Dynamic Type / dark-mode QA pass over every SPEC state (Appendix A) and writes the hand-off notes for the backend team.

## Conflict-avoidance rules (enforced in every agent prompt)

1. Each agent runs in its **own git worktree/branch** and may only write inside the paths it owns (table above).
2. Frozen contracts (`MetlyCore`, `MetlyData` schema, `Package.swift`, app target) are read-only for feature agents. Need a change? Describe it in the final report — the orchestrator applies it.
3. Features never import other features; cross-feature navigation = `router.push/present(...)` with a route from `MetlyCore`.
4. Builds go through `scripts/build.sh <Scheme>` which serialises `xcodebuild` across agents (machine has 8 GB RAM) and uses a per-worktree DerivedData.
5. Every agent finishes with: module builds, its tests pass, previews for every SPEC state it owns, and a report (files, shared-component candidates, contract change requests, open issues).

## Status (2026-10-03)

All waves merged on `main`; app + widget extension build with zero errors; **529 package tests pass** (15 test targets).
Verified on iPhone 17 Pro simulator (iOS 26): Home, QR fullscreen → Just Met, Scan (demo) → Scanned Card, Connect (Nearby demo) → Connected → Connection detail, People, Profile, dark mode, widget deep link.

### Next steps
- Backend team implements `docs/api/openapi.yaml` (+ `docs/api/README.md` rules); set `METLY_API_BASE_URL` per configuration — until then the app runs on `MockMetlyServer`.
- Signing: set `DEVELOPMENT_TEAM`; register `com.metly.app`, `com.metly.app.widgets`, App Group, Associated Domains (`metly.link` AASA), Sign in with Apple, Push, Pass Type ID `pass.com.metly.app.card`; Google OAuth iOS client → `MetlyGoogleClientID`.
- Device testing: Nearby/Tap Phones on two iPhones (MPC + NearbyInteraction thresholds), camera QR/OCR, Lock Screen widgets, Wallet pass (needs server signing).
- Polish backlog: QR screen fits without scrolling; App icon; String Catalog extraction for future locales; promote remaining shared-component candidates listed in agent reports (BottomActionBar ×3, ImageDownscaler ×3, ContactFieldRow ×2, follow-up due labels).
