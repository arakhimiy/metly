# Nameshake — Engineering Guide for Feature Agents

Read this fully, then `docs/PLAN.md`, then the SPEC sections for your screens (`prd/SPEC.md`).
The HTML prototype in `prd/` is for **behaviour only** — never copy its visuals, colors, fonts or custom controls.

## 1. Ownership rules (hard)

- You work in your **own git worktree/branch**. Write ONLY inside the paths your prompt lists.
- Read-only for you: `Packages/MetlyKit/Package.swift`, `Sources/MetlyCore`, `Sources/MetlyDesign`, `Sources/MetlyData/Schema`, `Sources/MetlyData/Container`, `Sources/MetlyData/Preview`, `Metly/`, `Metly.xcodeproj`, `docs/` (except paths explicitly given to you).
- Keep the public initialisers of your module's entry views (`*Entry.swift`) exactly as they are — the app's `RouteResolver` calls them. Replace the bodies. Add files freely inside your module.
- Need a contract change (new route, model field, service method, shared component)? Do NOT edit the frozen file. Work around it locally if you can and list the request in your final report under **Contract change requests**.
- Features never `import` other features.
- Commit your work on your branch (small logical commits are fine). Use the machine's global git identity — never set
  a repo-local `user.name`/`user.email` — and do NOT add `Co-Authored-By` trailers.

## 2. Build & test (8 GB machine — builds are serialised)

```bash
scripts/build.sh <Module>          # e.g. scripts/build.sh FeaturePeople   (fast, module only)
scripts/build.sh <Module> test     # runs Tests/<Module>Tests on the simulator
scripts/build.sh app               # whole app incl. widgets — run before you finish
scripts/build.sh all test          # every MetlyKit test target (what CI runs)
scripts/run.sh --local             # signed simulator build, launched against localhost:3000 (--mock, --demo)
```
`build.sh` builds unsigned (fast, no team) — fine for compiling and tests, but an unsigned app has no
App Group, so SwiftData can't open its store and the app shows a blank screen. Use `run.sh` to run it.
The script waits for a global lock, so a "waiting for another build" message is normal. Never call `xcodebuild` directly, never delete DerivedData of other checkouts, never boot extra simulators. Build after each meaningful chunk, not after every edit.

## 3. Architecture cheat-sheet

```
MetlyCore       AppRouter, routes (PushDestination / SheetDestination / CoverDestination), RootPhase,
                domain enums & values (CardDesign, ContactField, MeetingContext…), Brand, PlanLimits,
                AppServices (auth, sync, deferredLinks, subscriptions, push, entitlements, network, preferences)
MetlyDesign     toastHost, glassOrMaterial / prominentButtonStyle / secondaryButtonStyle, InitialsAvatar,
                SettingsIcon(field:), ProBadge, FeaturePlaceholder, ContactFieldKind.tint
MetlyCardKit    CardFaceView(design:content:), QRCodeView(payload:), QRCodeGenerator
MetlyData       SwiftData models: Profile, Card, Connection, FollowUp, Event, ConnectRequest
                descriptors: Card.live, Connection.live, FollowUp.open, Event.active, ConnectRequest.pendingIncoming
                context helpers: currentProfile(), defaultCard(), activeEvent(), cardToShare(), record(_:id:)
                card.faceContent(profile:audience:), PreviewSeed, View.metlyPreview(_:plan:online:)
MetlyNetworking API client + DTOs + mock server (Data & Sync agent) — see docs/api/README.md "Using the API from features"
MetlyCapture    shared context capture (People agent): CaptureDraft, ContextCaptureForm, FollowUpPolicy,
                .followUpLimitAlert, ContactSaver/.contactSaver, ContactLinks, LocationContextProvider,
                VoiceNoteRecognizer, CaptureChip, TagFlowLayout, .settingsAlert — API summary at top of MetlyCapture.swift
MetlySharedUI   data-aware shared UI: CardActionsMenu + CardAction + CardActionCoordinator (+ .cardActionAlerts),
                CardManagement (default/delete/limit rules), SafariView + .inAppBrowser(BrowserPage)
MetlyCardKit+   CardTemplateThumbnail, CardPaletteSwatch, CardProLockBadge, .cardFaceElevation(), CardFaceContent.sample,
                VCardBuilder / VCardParser, CardExporter (png/pdfSingle/pdfSheetA4/lockScreenWallpaper), ContactValueFormat
```

### Navigation
```swift
@Environment(AppRouter.self) private var router
router.push(.connectionDetail(id: person.id))          // same tab stack
router.open(.connectionDetail(id: id), in: .people)     // dismiss modals, switch tab, push
router.present(.qr(cardID: card.id))                    // full-screen cover
router.present(.share(cardID: card.id))                 // sheet (stacks above a cover automatically)
router.replaceTop(with: .cover(.connected(connectionID: id)))
router.dismiss()                                        // close top-most modal (use instead of @Environment(\.dismiss) for routed modals)
router.showToast("Removed", systemImage: "trash", undo: { person.restore() })
```
Local, feature-internal sheets/pickers/alerts may use plain SwiftUI state (`.sheet(isPresented:)`, `.alert`, `.confirmationDialog`). Cross-feature destinations must use the router.

### Data (offline-first)
- Read with `@Query(Card.live)`, `@Query(Connection.live)` etc. or `modelContext` helpers. Always exclude tombstones (`deletedAt == nil`).
- Mutate models directly, then call `record.markChanged()`. Delete with `record.markDeleted()` (soft delete; Undo = `record.restore()`). Never call `modelContext.delete` on synced models.
- Inserting: `modelContext.insert(Connection(fullName:…, source: .paper))` — new records start as `pendingUpsert`.
- Server-only actions (connect requests, card publishing/slug, public profiles, wallet pass) go through MetlyNetworking APIs (available from wave 2).
- Gating: `services.entitlements.limits` (`PlanLimits.free/pro`). On a blocked action present `.paywall(trigger:)` (or the limit alert from SPEC first, whose CTA opens the paywall).

### Previews
Every screen and every SPEC state you own gets a `#Preview` (Appendix A of SPEC lists them):
```swift
#Preview("People · empty") { NavigationStack { PeopleView() }.metlyPreview(.empty) }
#Preview("People · Pro offline") { NavigationStack { PeopleView() }.metlyPreview(.full, plan: .pro, online: false) }
```

## 4. Apple HIG rules (non-negotiable)

- **System components first**: `NavigationStack`, `List`/`Form` (`.insetGrouped` look), `Section` headers/footers, `Toggle`, `Picker` (menu / segmented / navigationLink styles), `Menu`, `DatePicker`, `Stepper`, `TextField` with proper `textContentType`/`keyboardType`/`submitLabel`, `PhotosPicker`, `ShareLink`, `ContentUnavailableView` for empty/error states, `.searchable`, `.refreshable`, `.swipeActions`, `.contextMenu(menuItems:preview:)`, `.confirmationDialog` / `.alert` for destructive confirmations (role `.destructive`, cancel `.cancel`).
- **No custom chrome**: no custom tab bars, nav bars, back buttons, segmented controls or toggles. Toolbar items via `.toolbar { ToolbarItem(placement:) }`. Large titles on tab roots, `.inline` on pushed detail screens and sheets. Sheets get `.presentationDetents` + drag indicator where appropriate; covers get a Close/Done toolbar button.
- **Typography**: Dynamic Type text styles only (`.body`, `.headline`, `.subheadline`, `.caption`…). No fixed point sizes in app UI (exception: card faces in CardKit, which scale with the card). Support up to accessibility sizes — let text wrap; use `ViewThatFits`/`AnyLayout` when HStacks overflow.
- **Color**: semantic colors (`.primary`, `.secondary`, `Color(.secondarySystemGroupedBackground)`, `.tint`) and `.accentColor`. No hex colors outside CardKit palettes. Must look right in Light, Dark and Increase Contrast.
- **SF Symbols** for every icon, with matching weights; `Label` for icon+text. Icon-only buttons need `.accessibilityLabel`.
- **Hit targets ≥ 44×44 pt**; `.contentShape(Rectangle())` on tappable rows.
- **Liquid Glass**: you get it for free on iOS 26 from system bars/sheets/toolbars. For floating custom chrome use `glassOrMaterial(in:)`; for primary CTAs `prominentButtonStyle()`. Never stack glass on glass; never hand-roll blur.
- **Feedback**: `.sensoryFeedback(.success, trigger:)` on success moments (connected, saved), `.selection` on picks. Toasts only via `router.showToast`.
- **Accessibility**: meaningful labels/values/hints, `.accessibilityElement(children: .combine)` for rows, Reduce Motion respected for custom animations, VoiceOver order sensible.
- **Permissions**: request in context, right before use, with a pre-explanation only when SPEC shows one. Handle denied state with a "Open Settings" button (`UIApplication.openSettingsURLString`).
- **Copy**: Title Case for buttons/titles, sentence case for footers/descriptions; use SPEC §7 copy, replacing the prototype name "Cardy" with `Brand.appName` / `Brand.proName` / `Brand.linkHost`.
- **Out of scope v1**: AI features, CRM integrations (CSV only), email sign-in. Do not show their entry points.

## 5. Swift rules

- Swift 6 language mode. UI modules default to `@MainActor` isolation; `MetlyCore`, `MetlyNetworking`, `MetlyCardKit` and `MetlyData` are nonisolated (mark services `@MainActor` explicitly there).
- async/await + `.task {}`; no Combine, no `DispatchQueue.main.async`, no completion handlers in new APIs.
- `@Observable` view models only when a screen has real logic; otherwise plain `@State` in the view. No singletons except those in `AppServices`.
- Small views: split anything over ~150 lines into subviews in the same file or a sibling file.
- Use `FormatStyle` (`.formatted(date:time:)`, `Date.RelativeFormatStyle`) — no `DateFormatter` strings.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`). Test logic (grouping, parsing, limits, merges), not layout.

## 6. Final report (your last message)

1. Summary of what was built (screens/states covered, SPEC IDs).
2. Files added/changed (paths).
3. Build + test results (paste the ✅/❌ lines).
4. **Contract change requests** (route/model/service/Package.swift/Info.plist changes you need), with exact proposed code.
5. **Shared component candidates** (things other features could reuse) with file paths.
6. Known gaps / TODOs / open questions.
