# Cardy — session state

## Files
- `Cardy App v4.dc.html` — current prototype (iOS-native, teal tint). v1–v3 kept as history.
- `CardFace.dc.html` — card renderer (9 templates), used via `<dc-import name="CardFace" vm="…">`.
- `vendor/phosphor/*` — local Phosphor icon fonts (regular/fill/bold), linked in helmet (CDN broke publish).

## Decisions
- UI follows iOS system components (large titles, inset grouped lists, switches, segmented, menus, alerts, sheets, floating island tab bar). User chose "iOS uslubi qolsin" over Nocturne rules (outlined buttons, no pure black/white, weight ≤500) — intentional deviation.
- Accent: teal (#0F766E fill / #2DD4BF dark tint). Tweak `tint` offers nocturne/blue/cardy.
- Home: no date, no link under card; 2 CTAs (Show QR, Share); long-press context menu.
- Exchange = two-way swap with Cardy users (Nearby / Tap Phones), no QR. QR fullscreen = share with non-app users.
- Photos/logos rendered as background-image (bundler treated `{{ photo }}` src as missing file).

## Tweaks (props)
appTheme, tint, tabStyle, demoData (full/empty), offline, start, freePlan.
Note: user's saved values offline=true, demoData=empty make Home/People look empty.

## Done in v4
Setup (profile → permissions → first card), iOS permission alerts, Settings subpages (Notifications, Privacy & Data, Subscription, Help), Delete Account, Card Settings (rename/default/reorder/duplicate/delete), Exchange states (empty/declined/timeout/incoming), invalid QR, publish failed, People skeleton.

## v7 — HIG / UX pass (Cardy App v7.dc.html, v6 kept)
- Home event banner: removed nested "End Event" button (mis-tap risk); End lives in Event detail.
- Removed duplicate "New Card" carousel tile; page dots hidden with 1 card.
- Connect icon: arrows (swap) → person-plus everywhere.
- Profile: removed duplicate Connect Requests toggle (in Notifications). Avatar "EDIT" 10px strip → camera badge.
- 44pt hit targets: close/more/dismiss/clear buttons; text links → buttons (Sign In, Restore, Terms, Privacy, web Open/Remove).
- Chips 36pt, pills 36pt, segmented 32pt (UISegmentedControl).
- Dynamic Type: contact subtitle wraps, list names ellipsize. Apple button 17pt semibold. Onboarding last step "Get Started".

### v7 UX fixes (round 2)
- People: long-press menu (Open / Add Note / Remove) + hint; Remove has Undo toast.
- Contact "Edit" → "Edit Note". Web form shows what's missing; Send disabled.
- Email sign-in validation with inline error. Home Snooze → duration menu (Tomorrow / 3 days / Next week / Custom).
- Date pickers min = today. Paywall auto-renew terms. Paste Link in Paper mode too. Follow-ups/Events rows removed from Profile.

## v8 — Section 7: web share-back (Cardy App v8.dc.html)
- Web page: auto share-back sheet (name, phone/Telegram ≥1, met at, consent, Send & Save, Skip); Copy on phone/email; Message on Telegram; Smart App Banner (iOS); soft CTA after save.
- Platforms (state webPlat): ios (contact preview sheet), android (Create contact intent + .vcf fallback with hint), inapp (Telegram header + "Open in browser to save contact").
- Confirmation, card unavailable (paused/deleted, no personal data). Duplicate phone/Telegram merges silently.
- Owner: push "X shared their contact with you · event", via web badge in People, tap → capture sheet; card stats row on Home.
- "Who did you just meet?" sheet after QR (open >2s) or share sheet (after a share action). Same first name share-back → merged + "Merged" row/toast.
- Deferred deep link screen (phase 'deferred'); Get Cardy CTA leads there. Offline QR toggle on QR screen.

## Open / next
- Card stats (views/scans), web page desktop + App Store redirect, app icon + launch screen.
- Light mode + Dynamic Type pass across all screens.
- Full i18n (only core strings in uz/ru).
- Offered: Claude Code handoff package. Local repo "Business Card IOS" attached but not yet read.
- Always ask user before changing the project.
