# Card templates v2: printed-card quality, logo, per-card field toggles

Status: **implemented** (2026-11-13), not committed. The owner approved the plan ("Yes, start") and asked that creating and editing a card be very easy, which added the UX changes in §4.4.

## 1. The owner's HTML question

**Recommendation: keep the card faces in SwiftUI. Use HTML only to mirror them on the web card page, and for this review's mockups.**

What the code shows:

- One renderer draws every face in the app: `CardFaceView` / `CardFaceCanvas` in `MetlyCardKit/Face`. It covers about 20 call sites, from Home, the picker and the editor to Connect, Scan and People.
- The widgets (`MetlyWidgetKit/Views/CardWidgetView.swift`) render `CardFaceView` directly. WidgetKit cannot host a `WKWebView`, so an HTML face would not render in widgets.
- Image, PDF and print export and the Lock Screen wallpaper (`CardExporter`, `CardPrintLayout`, `LockScreenWallpaperView`) render the same view through `ImageRenderer`. Using HTML here would mean an off-screen web view snapshot, which is asynchronous, slower and blurrier at print sizes, and wouldn't run in an extension.
- The Wallet pass is built on the server from standard pass fields. It never shows the face, so neither option affects it.
- The web card page (`backend/src/web/page.ts`) **already** draws an HTML/CSS approximation of each template (`.tpl-*` classes). It has to be updated alongside the app either way.

So "make them in HTML" would cost us widgets and crisp export and save nothing. The quality problem lies in the design, not in the technology. SwiftUI can draw foil gradients, deboss, contour lines and grain natively, and the drawing stays vector-sharp at any size.

## 2. Template set

### 2.1 Constraints that shape it

- `CardTemplate` raw values travel on the wire (`backend/src/records/wire.ts`, `z.enum([...9 ids])`) and live in SwiftData as part of `CardDesign`. Adding new ids would break older installed apps that decode a card from sync. So we **keep the nine ids and redesign what each one looks like**. Only the display name changes: `CardTemplate.title` gets explicit names instead of `rawValue.capitalized`.
- Every length stays a percentage of the card width (`style.u(_:)`), so one layout works everywhere from a 56 pt thumbnail to a 1,004 px print export.
- The palettes (6 palettes × light/dark) still apply. Templates with a finish derive the finish colour from the palette (see 2.4).

### 2.2 Shared typographic system (all templates)

Real printed cards share the same few typographic rules. Today's faces break most of them.

| Element | Rule |
|---|---|
| Margin | **8 %** of the width on every side (today 6–7 %). Nothing touches it except edge finishes. |
| Name | One focal size per template. Weight is semibold, or medium for serif. Tracking is −1 % at large sizes and +12 % in caps styles. |
| Title | 2.9–3.2 %, muted, never on the same line as the company. |
| Company | Either a **wordmark** (caps, +18 % tracking) or the logo. It is no longer glued to the title with " · ". |
| Contacts | 2.7–2.9 %, tabular figures. They use a muted **text label** (`tel`, `mail`, `web`) or no marker. SF Symbol icons are kept only in Duotone and Centered. Icon-per-line is the main thing that makes the current set look generated. |
| QR | Smaller (18–20 %, today 23–24 %), always black on white. On dark cards it sits on a plate with a 1.6 % radius and no shadow. |
| Colour | One accent use per card at most: the finish or the name, never both. |

### 2.3 The nine templates

Each template has one focal element (in bold below). The reference photos it follows are given in brackets.

| id (wire) | New name | Layout | Typography | Finish |
|---|---|---|---|---|
| `minimal` | **Classic** | Company wordmark or logo top-left. **Name + title** bottom-left. Labelled contacts in a right-aligned column at the bottom right. QR top-right when on. [MOCK-UP white back] | Name 6.2 % semibold; labels muted lowercase | Uncoated paper grain (very light) |
| `professional` | **Monogram** | **Debossed monogram**, or the logo pressed as a deboss, filling the left 42 % at 70 % of the height. Name in the accent colour, title, then contacts on the right. [black card, debossed "H", cyan name] | Name 4.6 % semibold in the accent colour | Deboss: same colour as the card, inner highlight + inner shadow |
| `modern` | **Foil** *(Pro)* | **Holographic foil bar** (7 % × 46 %) top-left. Name in caps with an italic tagline. Contacts lower-left. Company as a **vertical outlined wordmark** on the right edge. [PHENOMINAL] | Name 4.4 % caps +8 %; title italic | Iridescent foil gradient with a soft specular band; matte black stock grain |
| `bold` | **Wordmark** | **Company (or first name) huge**, filling about 80 % of the width. A small tagline under it. Two contacts bottom-left. Logo or ✱ mark bottom-right. [MOCKUP white stack] | Wordmark 13–15 % heavy, −3 % tracking, auto-fit to one line | none (pure type) |
| `gradient` | **Aurora** *(Pro)* | Full-bleed **vivid gradient** with fine contour lines. Name as a wide-tracked wordmark in the centre. Website or handle bottom-left. Pairs with a black "back" in export. [BROOKS] | Wordmark 8 % caps +14 % | Mesh-like 3-stop gradient + 1 px contour lines at 18 % white |
| `split` | **Duotone** | Accent panel on the left 36 %, with the **logo or photo** centred. Name, title, rule and contacts with small icons on the right. | Name 5.4 % semibold | Panel in a flat accent colour; hairline divider |
| `terminal` | **Terminal** | Kept for developers but cleaned up: a prompt line, the name with a cursor, then `key value` pairs aligned in two columns. | SF Mono throughout | none |
| `stack` | **Centered** | A centred **logo or photo**, name, title, a short accent rule, then contacts as one centred line of `·`-separated items. [blue "DESIGN" card, without the glow] | Name 5.6 % semibold, centred | Thin accent rule only |
| `editorial` | **Editorial** *(Pro)* | Serif **name**, italic title, then a foil hairline. Contacts set like a colophon. Optional metal-foil logo. [GEARWORKS silver foil] | New York (serif) 6 %, medium | Metallic foil (silver, gold or rose by palette) on the rules and the logo |

Pro set: **Editorial, Foil, Aurora** (today it is Editorial only). The finish templates are the premium ones. Cards already on Foil or Aurora keep them, because the server checks only a *switch to* a Pro template (`PRO_TEMPLATES`). **Owner decision:** make Foil and Aurora Pro, or keep them free?

### 2.4 Finishes (new `MetlyCardKit/Face/Finishes/`)

All finishes are pure SwiftUI drawing, so they work in widgets, `ImageRenderer` and print, with no image assets.

- `FoilFill`: a `ShapeStyle` built from a multi-stop gradient. Holographic is violet → cyan → mint → amber → pink. Metallic gold, silver and rose use 5 stops with a bright specular band. The palette chooses it: ink and ocean get holographic, sand and ember get gold, graphite and snow get silver.
- `Deboss`: text or logo-mask filled with the card colour plus `.shadow(.inner(...))` light/dark pairs. This is available since iOS 16 and renders in `ImageRenderer`.
- `ContourLines`: a `Canvas` that draws 14–18 offset sine contours, with the stroke at `hairline`.
- `PaperGrain`: a `Canvas` that draws seeded noise dots at 3–5 % opacity. It is skipped when the face is narrower than 160 pt (widgets and thumbnails) to keep them fast.
- Aurora colours come from the palette accent through three hue-shifted stops. Ink gives violet → magenta → orange, ocean gives indigo → teal → lime, and so on. Light appearance raises the lightness.

`nonisolated` goes on each custom `Shape` (a Swift 6 requirement in this package).

## 3. Logo

### 3.1 What exists already

- `Profile.logoData` (SwiftData, external storage) syncs through the media endpoint as `profile.logoUrl`. The code is in `SyncEngine+Images.swift`.
- The editor's Media tab has a PhotosPicker for the logo (`MediaPickerSection`, PNG, downscaled) and a per-card **Show on Card** switch (`design.showLogo`).
- Only `professional` draws the logo (`templateShowsLogo`). The web page also shows it only for `professional`.

### 3.2 Decision: keep the logo on the profile, not per card

Name, title and company are profile-level too (`CardContentFactory` reads them from `Profile`), so one logo matches one company. A per-card logo would need a new card media column, a per-card upload route, and a SwiftData schema version for very little gain. Each card already chooses whether to show the logo.

### 3.3 What changes

1. **Every template that has a logo slot shows it** when "Show logo" is on. That is Classic, Monogram (as a deboss), Foil, Wordmark (corner mark), Duotone, Centered and Editorial; Aurora and Terminal have no slot. `templateShowsLogo` follows this list.
2. **Auto-trim on import:** the transparent margin, or a uniform white or black border, is cropped to the content's bounds. The image is kept at 1,024 px max as PNG. Most logos people have arrive padded, which makes them look tiny on the card. I won't build a manual crop UI: a logo has nothing to frame, and auto-trim is what a print shop would do.
3. **Logo style: Original | One-colour.** One-colour uses the logo's alpha as a mask and fills it with the template's ink: the foil, the deboss or the foreground colour. This is how a printed foil logo looks. The option is enabled only when the image has transparency. The footer explains: "Use a PNG with a transparent background for one-colour logos."
4. **The create flow offers the logo** on the Details step, next to the photo. Today it's only reachable in the editor's Media tab.

## 4. Field toggles

### 4.1 What exists already

- Per-card contact selection: `Card.visibleContactIDs` and the "Show on This Card" switches in `CardFieldsSection`. These are synced as `design.visibleContacts`.
- `design.showPhoto`, `design.showLogo` and `design.showQR` are on the wire and in the editor (Media tab).

### 4.2 What's missing and what changes

- **Job title and company switches** are new.
- The name is always shown. A card without a name isn't a card.
- **One place for all of it:** the editor's "Fields" tab becomes **Show on This Card**, with a group for each kind of element:
  - *Identity:* Job Title, Company, Photo, Logo (with Logo Style)
  - *Contacts:* the current per-entry switches
  - *Code:* QR Code
  The Media tab keeps only picking and removing images.
- A switch for an element the chosen template can't show stays enabled, with a footer note like today's "The Wordmark template doesn't show a photo."

### 4.3 Storage and sync

- **Wire:** `design.showJobTitle?`, `design.showCompany?` and `design.logoStyle?` (`"original" | "mono"`) are optional in `CardDesignObject`. When a field is absent it is treated as true or `original`, so designs written by older apps compare equal and validate.
- **Server:** this needs no Prisma migration, because `design` is a `Json` column. The changes are the zod schema, `openapi.yaml`, the web page and `snapshot.ts` (the CardSnapshot `jobTitle`/`company` are blanked when hidden, so connections never receive what the owner hid).
- **App, SwiftData:** `CardDesign` is a Codable composite inside the frozen V1–V3 schemas. Changing its shape would change those schemas' hashes and break on-disk migration. So:
  - Add `MetlySchemaV4`. `Card` gains `faceOptionsData: Data? = nil`, which holds `CardFaceOptions { showJobTitle, showCompany, logoStyle }` as JSON. The migration from V3 to V4 is lightweight.
  - Freeze the current file as `ModelsV3.swift`, following the existing V1/V2 pattern.
  - The sync mappers merge `CardFaceOptions` into and out of the `design` JSON.
- **Rendering:** `CardContentFactory` applies the options to `CardFaceContent`. A hidden title or company becomes "", and the logo style is passed through. As a result, Home, widgets, exports, the Lock Screen, Share and Connect all honour the toggles without touching their call sites. `WidgetSnapshotBuilder` applies the same options.

## 5. Surfaces to verify

| Surface | File | Check |
|---|---|---|
| Picker (Create → Templates) | `FeatureCards/Create/CreateGalleryStep.swift`, `Components/TemplateGrid.swift` | New names, Pro badge, user's own content |
| Editor preview | `Editor/EditorPreviewHeader.swift` | Live toggles |
| Home carousel | `FeatureHome/Home/Cards/CardCarousel.swift` | Light and dark |
| Widgets | `MetlyWidgetKit/Views/CardWidgetView.swift` | Grain off at small sizes, logo thumbnail |
| Export (image/PDF/print, Lock Screen) | `MetlyCardKit/Export/*` | Bleed for edge finishes (Foil bar, Duotone panel, Aurora) |
| Web page | `backend/src/web/page.ts` | CSS mirror of the nine faces, logo on all slots, hidden title/company |

## 6. Tests

- `MetlyCardKitTests`: `CardFaceModel` honours the options; `templateShowsLogo` and `templateShowsPhoto` tables; logo auto-trim on fixtures (transparent PNG, white-boxed JPG).
- `MetlyDataTests`: V3 → V4 migration keeps cards; the sync round-trip of `CardFaceOptions` through `design` JSON.
- `FeatureCardsTests`: the content factory blanks hidden title and company for every audience.
- Backend: zod accepts old and new designs; the snapshot blanks hidden fields; page snapshot tests for each template.
- Screenshots: all nine templates × light/dark, with and without a logo, as user "asr", via `scripts/run.sh --local`.

## 7. Out of scope

- Two-sided cards (front and back). Aurora's "black back" appears only in exports for now.
- Custom fonts beyond the four `CardFont` families.
- A manual crop UI for the logo.

## Decisions taken

1. Foil and Aurora are **Pro**, together with Editorial (`CardTemplate.isPro`, server `PRO_TEMPLATES`).
2. The display names are the ones in §2.3. The wire ids are unchanged.
3. The logo stays on the **profile**: one logo, with a switch on each card.
4. Foil, Monogram, Duotone and Editorial always press a transparent logo in their own ink. The Original / One Color choice applies to Classic, Wordmark and Centered.

## 4.4 Easy create and edit (owner request)

- **Create** has three steps: Templates → Style → Details. The "How do you want to start?" screen is gone; Blank was the Classic template anyway. The logo and photo are added inline on Details, and nothing is a separate step.
- **Editor** has three tabs: Template · Style (colour + type) · Details (title, company, logo, photo, contacts, QR). It used to have five. The Alignment control appears only for the template that uses it (Wordmark).
- Picking a logo or photo switches it on for the card. An empty job title or company shows "Add it in Profile" and its switch is disabled.
