# Metly — Product & Functional Specification

> Derived from the HTML prototype **"Cardy App v8.dc.html"** (source of truth), `CardFace.dc.html` (card renderer), and `plan.md` (decision log).
> The prototype was named **Cardy**; the native iOS product is **Metly**. All user-facing copy below is quoted verbatim from the prototype (with "Cardy"). Implementation should substitute "Metly" (see §9 Q1).
> The prototype is **not** the visual-design source. This document captures product behaviour, structure, states, data and copy only.
> Prototype "today" is fixed to **Saturday, Sep 26, 2026**; sample user is **Aziza Karimova, Product Designer, Tezkor Labs** (Tashkent, Uzbekistan). Phone placeholders default to `+998`.

---

## Table of contents

1. Product summary
2. Information architecture (tabs, navigation, screen catalog, per-screen specs)
3. Flows
4. Data model
5. Backend interactions (candidate API)
6. iOS native capabilities
7. Copy catalog (alerts, toasts, pushes, i18n)
8. Prototype tweaks and what they imply
9. Open questions / ambiguities
- Appendix A — Prototype state catalog (76 states → screen IDs)
- Appendix B — CardFace template specification
- Appendix C — Suggested work packages for parallel implementation

---

## 1. Product summary

### 1.1 What the app does

Metly is a **digital business card + lightweight personal CRM for in-person networking**. Tagline in prototype: *"Never forget someone you meet."* / App Store subtitle: *"Remember everyone you meet."*

Three product pillars (mirrors the 3 onboarding pages):

1. **Share your card** — the owner designs one or more digital cards (9 templates), each with a public link (`cardy.link/c/{slug}`) and QR code. Recipients without the app open a web page; recipients with the app can do a two-way **Connect** (Nearby / Tap Phones).
2. **Context saves itself** — every new connection is automatically stamped with *event, place and time*; the owner adds a **private note** (typed or by voice) and **tags**.
3. **Follow up on time** — one-tap reminders ("Tomorrow / In 3 days / Next week / Pick a date") that tell you *why* to follow up and via which channel (Telegram / Email / Call). **Event mode** groups everyone met at an event and produces a summary.

Additional value:
- **Web share-back**: a web recipient can send their own contact back to the owner ("Exchange contacts") in one step, so the owner captures people who don't have the app.
- **Paper card scanning** (on-device OCR) and scanning other people's Cardy/vCard QR codes.
- **AI**: card design generation, per-person recap ("What did we talk about?"), pre-event briefing / event recap.
- **Export**: PNG/PDF (print-ready), Apple Wallet pass, Lock Screen wallpaper; event export to CSV / Google Sheets / HubSpot / amoCRM / Bitrix24.
- **Widgets**: follow-ups, QR on Lock Screen / Home Screen.

### 1.2 User types

| Actor | Has app? | What they do |
|---|---|---|
| **Owner** | Yes (signed in) | Creates cards, shares QR/link, connects, captures context, follows up, runs events, pays for Pro. |
| **Peer (app user)** | Yes | Two-way Connect with the owner (Nearby / Tap Phones / scan owner's QR in-app / async connect request). Both sides exchange chosen cards. |
| **Web recipient** | No | Scans QR with the phone camera or opens the link → public web card page (only **Public** fields). Can Save to Contacts, copy phone/email, message on Telegram, and **share their contact back** (name + phone or Telegram + optional "met at"). Platforms: **iOS Safari**, **Android Chrome**, **in-app browser (Telegram)**. |
| **Deferred installer** | Installs after web visit | Tapped "Get Cardy"/Smart App Banner on the web page, installs, first launch shows "You met {owner} at {event}. Connect?" (deferred deep link). |

### 1.3 Plans (Free vs Pro)

| Capability | Free | Pro ("Cardy Pro") |
|---|---|---|
| Cards | **2** (create/duplicate blocked beyond 2) | Unlimited |
| Active follow-up reminders | **5** | Unlimited |
| Active events | **1** | Unlimited (several at once) |
| AI card designs | **3 / month** (results restricted to Free palettes) | 30 / month |
| AI recap / briefing | Shown with PRO badge; footer says "3 free recaps left this month" | Included |
| Export event to CSV / CRM | Locked (paywall) | Included |
| Templates / palettes | Editorial template, Ocean and Ember palettes locked | All |
| Pricing | — | **Yearly $19.99** ("$1.67 a month, billed yearly", badge "Save 44%"), **Monthly $2.99** |
| After cancel | — | "You keep Pro until the end of this billing period. Cards beyond two become read-only after that." |

### 1.4 Glossary

- **Card** — a designed business card (template + palette + typography + which fields to show + media) with its own **slug/link** and QR. One card is the **Default card** ("Used for Connect, events and widgets").
- **Contact field** — Phone, Email, Telegram, Website, LinkedIn (fixed order). Each has a **privacy level**: `Public` (anyone with your link), `Connections` (people you've connected with), `Private` (only you; never appears on any card).
- **Connection / Person** — someone the owner met (shown in the **People** tab). Sources: Nearby, Tap Phones, scanned QR, paper card, web share-back, "Who did you just meet?", connect request, deferred link.
- **Context ("Where You Met")** — event, place (+city), time; auto-filled ("Auto" badge with magic wand).
- **Private note** — text + tags, visible only to the owner ("Note · 🔒 Only You").
- **Follow-up / Reminder** — what to do, when (date + time, default 10:00), via channel (Telegram/Email/Call). Groups: Overdue, Today, This Week, Later, Done.
- **Event (Event mode)** — a named event with place, dates and a card to share. While active, every new connection is auto-tagged with it. Ends manually or automatically after the last day, producing a summary.
- **Share-back** — a web recipient's contact submitted from the owner's public page.
- **Connect** (a.k.a. "Exchange" in plan.md) — two-way swap with other app users via **Nearby** or **Tap Phones**. Not QR-based. QR is for non-app users.
- **Pause links** — makes the public page show "This card isn't available right now"; printed QR codes work again on resume.

---

## 2. Information architecture

### 2.1 Root phases

The app has distinct root phases (prototype `state.phase`):

| Phase | Screens | Notes |
|---|---|---|
| `welcome` | ONB_WELCOME | First launch / after sign-out / after account deletion. |
| `signin` | AUTH_SIGNUP | |
| `check` | AUTH_CHECK_EMAIL | Email magic link sent. |
| `setup` | SETUP_PROFILE → SETUP_PERMISSIONS | After first sign-in. Ends by launching CARD_CREATE. |
| `app` | Tab bar + everything else | |
| `deferred` | DEFERRED_WELCOME | First launch after install from web page. |
| `web` | WEB_* | **Not part of the iOS app** — the public web page simulated inside the phone frame. Separate web deliverable. |

### 2.2 Tab bar

4 tabs (floating "island" style by default; "classic" alternative — see §8):

| Tab | ID | Icon (prototype) | Badge |
|---|---|---|---|
| Home | `HOME` | house | — |
| Scan | `SCAN` | qr-code | — |
| People | `PEOPLE` | users-three | Count of **pending connect requests** |
| Profile | `PROFILE` | user-circle | — |

Prototype rule: tab bar is visible on tab roots and on Settings sub-pages (`SETTINGS_*`, `CARD_SETTINGS`); hidden on other pushed screens (connection detail, follow-ups, event detail, scanned card, paper review, widgets) and all modals. (See §9 Q32 — iOS convention keeps the tab bar on pushed screens.)

Tab bar on SCAN renders in dark/camera styling.

### 2.3 Navigation map

```
ONB_WELCOME ─Skip/Get Started→ AUTH_SIGNUP ─Apple/Google/"Sign In"→ SETUP_PROFILE → SETUP_PERMISSIONS → [app] + CARD_CREATE
                                  └─Email Continue→ AUTH_CHECK_EMAIL ─Open Mail(link)→ SETUP_PROFILE

[app] TabBar
├─ HOME
│   ├─ avatar → PROFILE tab
│   ├─ event banner → EVENT_DETAIL (push) → START_EVENT(edit) sheet / AI_INSIGHT sheet / EVENT_EXPORT sheet / End → EVENT_ENDED (cover)
│   ├─ "Start Event" row → START_EVENT sheet
│   ├─ Follow Up Today "See All" → FOLLOWUPS (push) → REMINDER_EDIT sheet
│   │     card buttons: channel action (external app), Snooze menu, Done
│   ├─ My Cards "+ New Card" → CARD_CREATE (cover)   [Free limit alert]
│   ├─ card thumbnail tap → QR_FULLSCREEN (cover); long-press → CARD_PREVIEW_MENU
│   ├─ card "…" → MENU_CARD_ACTIONS
│   ├─ "Show QR" → QR_FULLSCREEN ; share icon → SHARE_SHEET
│   └─ Recent "See All" → PEOPLE tab ; row → CONNECTION_DETAIL
├─ SCAN (QR Code | Paper Card)
│   ├─ QR detected (Cardy link) / Paste Link → SCANNED_CARD (push) → Connect → CONNECTED (cover) ; Add to Contacts → ADD_CONTEXT sheet
│   ├─ QR not a card → ALERT_INVALID_QR
│   ├─ Paper shutter → PAPER_REVIEW (push) → Save → CONNECTION_DETAIL ; OCR fail → ALERT_PAPER_NOT_READ
│   └─ camera denied state
├─ PEOPLE
│   ├─ nav "Connect" (person-plus) → CONNECT (cover) → CONNECTED (cover) ; INCOMING_REQUEST overlay
│   ├─ Requests: Accept / Decline
│   ├─ row → CONNECTION_DETAIL (push) [web share-back w/o note → ADD_CONTEXT sheet]
│   │     → REMINDER_EDIT sheet, AI_INSIGHT sheet (recap), Remove/Block alerts
│   ├─ swipe: Note / Remove ; long-press: MENU_PERSON_ROW
│   └─ Events filter card → EVENT_DETAIL (push)
└─ PROFILE
    ├─ field privacy → MENU_FIELD_PRIVACY ; Appearance → MENU_APPEARANCE ; Language → MENU_LANGUAGE
    ├─ Cards row → MENU_CARD_ACTIONS
    ├─ Widgets → WIDGETS_GALLERY (push)
    ├─ Preview Public Page → (web page; in-app SFSafariViewController)
    ├─ Cardy Pro → SETTINGS_SUBSCRIPTION (push) → PAYWALL (cover)
    ├─ Notifications → SETTINGS_NOTIFICATIONS ; Privacy & Data → SETTINGS_PRIVACY → SETTINGS_DELETE_ACCOUNT ; Help & Support → SETTINGS_HELP
    └─ Sign Out → ALERT_SIGN_OUT → ONB_WELCOME

MENU_CARD_ACTIONS: Copy Link | Share… (SHARE_SHEET) | Show QR Code (QR_FULLSCREEN) | Connect Nearby (CONNECT) | Edit Card (CARD_EDITOR)
                   | Card Settings… (CARD_SETTINGS) | Export… (CARD_EXPORT) | Set as Default | Delete Card (alert)
QR_FULLSCREEN → Connect Nearby (CONNECT) | Share (SHARE_SHEET) | Done → [JUST_MET sheet if QR was open > 2 s]
SHARE_SHEET → targets / Copy Link / Add to Apple Wallet (CARD_EXPORT wallet) / Save Image or PDF (CARD_EXPORT png) → [JUST_MET after a share action]
Any Pro-gated action → PAYWALL (cover) → returns to originating route
Pushes: PUSH_CONNECT_REQUEST → PEOPLE ; PUSH_FOLLOWUP → FOLLOWUPS ; PUSH_SHAREBACK → ADD_CONTEXT / CONNECTION_DETAIL
```

### 2.4 Screen catalog

Presentation types: **Tab** root, **Push** (navigation stack), **Cover** (full-screen modal, slides up), **Sheet** (bottom sheet; "large" = top inset 54pt), **Overlay** (menu, context menu, alert, toast), **System** (iOS prompt / notification / widget), **Web**.

| # | ID | Title (prototype) | Type | Entry points |
|---|---|---|---|---|
| 1 | ONB_WELCOME | (3 pages) | Root | First launch, sign-out, account deleted |
| 2 | AUTH_SIGNUP | "Create your Cardy" | Root/push | Welcome Skip / Get Started; Back from Check Email |
| 3 | AUTH_CHECK_EMAIL | "Check Your Email" | Push | Email Continue (valid) |
| 4 | SETUP_PROFILE | nav "Your Profile" / "About You" | Root | After sign-in |
| 5 | SETUP_PERMISSIONS | nav "Permissions" / "Allow Access" | Push | Setup Continue |
| 6 | DEFERRED_WELCOME | "Welcome to Cardy" | Root | First launch after install via web page |
| 7 | HOME | "Hi, {first}" | Tab | Tab bar, Deferred "Not Now", many "Done"s |
| 8 | SCAN | "Scan Card" | Tab | Tab bar, Retake from Paper |
| 9 | PEOPLE | "People" | Tab | Tab bar, Recent See All, push tap, CONNECTED Not Now |
| 10 | PROFILE | "Profile" | Tab | Tab bar, Home avatar |
| 11 | FOLLOWUPS | "Follow-ups" | Push | Home See All, PUSH_FOLLOWUP tap |
| 12 | EVENT_DETAIL | {event name} | Push | Home banner, People→Events card, EVENT_ENDED "Add Notes…" |
| 13 | CONNECTION_DETAIL | {person name} | Push | People row, Recent row, after Save in CONNECTED/PAPER, menus |
| 14 | SCANNED_CARD | "Scanned Card" | Push | Scan QR, Paste Link |
| 15 | PAPER_REVIEW | "Paper Card" | Push | Scan paper shutter / frame tap, "Enter Manually" |
| 16 | WIDGETS_GALLERY | "Widgets" | Push | Profile → Widgets |
| 17 | SETTINGS_NOTIFICATIONS | "Notifications" | Push | Profile |
| 18 | SETTINGS_PRIVACY | "Privacy & Data" | Push | Profile |
| 19 | SETTINGS_SUBSCRIPTION | "Subscription" | Push | Profile → Cardy Pro |
| 20 | SETTINGS_HELP | "Help & Support" | Push | Profile |
| 21 | SETTINGS_DELETE_ACCOUNT | "Delete Account" | Push | Privacy & Data |
| 22 | CARD_SETTINGS | "{Name} Card" | Push | Card menu "Card Settings…" |
| 23 | CARD_CREATE | "New Card" wizard | Cover | Home + New Card, end of setup |
| 24 | CARD_EDITOR | "{Name} Card" | Cover | Card menu "Edit Card", Card Settings "Edit Design" |
| 25 | CARD_EXPORT | "Export" | Cover | Card menu "Export…", Share sheet actions |
| 26 | CONNECT | "Connect" | Cover | People nav button, QR "Connect Nearby", card menu, Empty-state "Open Connect" |
| 27 | CONNECTED | "You're Connected" | Cover | Nearby accept, incoming accept, Scanned "Connect" |
| 28 | QR_FULLSCREEN | (name) | Cover | Home Show QR / card tap, card menu, Connect empty-state "Show QR" |
| 29 | PAYWALL | "Cardy Pro" | Cover | Any gated action, Subscription "Upgrade"/"Change Plan" |
| 30 | EVENT_ENDED | "{event} Ended" | Cover | End Event confirm |
| 31 | SHARE_SHEET | (card + link) | Sheet | Home share icon, QR Share, card menu, Create "Share Now", Export "Share" |
| 32 | START_EVENT | "Start Event" / "Edit Event" | Sheet | Home Start Event row, Event detail Edit |
| 33 | ADD_CONTEXT | "Add Context" | Large sheet | Scanned "Add to Contacts", web share-back row/push |
| 34 | JUST_MET | "Who did you just meet?" | Sheet | After QR_FULLSCREEN (>2 s) or after a share action |
| 35 | REMINDER_EDIT | "New Reminder" / "Edit Reminder" | Large sheet | FOLLOWUPS +, row tap, Snooze "Custom…", Connection detail |
| 36 | AI_INSIGHT | recap / briefing | Sheet | Connection "What did we talk about?", Event "Pre-event Briefing"/"Event Recap" |
| 37 | EVENT_EXPORT | "Export" | Large sheet | Event detail / Event ended "Export to CSV or CRM" |
| 38 | INCOMING_REQUEST | "{name} wants to connect with you" | Overlay sheet in CONNECT | Live incoming request while CONNECT open |
| 39 | CARD_PREVIEW_MENU | card preview + menu | Overlay | Long-press card thumbnail (480 ms) |
| 40–47 | MENU_* | pull-down menus | Overlay | see §2.6 |
| — | ALERT_* | ~26 alerts | Overlay | see §7.1 |
| — | TOAST | HUD toast, optional Undo | Overlay | see §7.2 |
| — | PUSH_* | notifications | System | see §7.3 |
| — | WIDGET_* | 5 widgets | System | see §2.5.16 |
| — | WEB_* | 7 web surfaces | Web | see §2.7 |

### 2.5 Screen specifications (iOS app)

Conventions: "→" = navigation; *italic* = copy; `[Pro]` = gated on Free plan.

#### 2.5.1 ONB_WELCOME
- **Purpose**: 3-page value carousel.
- **Elements**: top-right **Skip** (→ AUTH_SIGNUP); illustration; title; subtitle; page dots (3); primary button *Continue* (pages 1–2) / *Get Started* (page 3) → AUTH_SIGNUP.
- **Pages**:
  1. Two overlapping card illustrations. *"Never forget someone you meet."* / *"Share your card, remember where you met, and follow up on time."*
  2. Contact-context illustration (Jasur Toshmatov, Payline; Event: Tashkent Tech Week; Place: Hyatt Regency; Time: Today, 14:32; note with mic icon). *"Context saves itself."* / *"Event, place and time are added the moment you connect. Add a note by voice."*
  3. Notification illustration (*"Follow up with Jasur Toshmatov"* / *"Design review you promised at Tashkent Tech Week."*) + chips Tomorrow / In 3 days / Next week. *"Follow up on time."* / *"Pick a day in one tap. Cardy reminds you why, so you know what to say."*

#### 2.5.2 AUTH_SIGNUP
- **Title**: *"Create your Cardy"*; subtitle *"It takes a minute. You can make your first card right after."*; **Back** → ONB_WELCOME.
- **Buttons**: *Continue with Apple* (Sign in with Apple), *Continue with Google*, divider *or*, inline grouped **Email** field (placeholder *you@company.uz*), *Continue*.
- **Validation (on Continue)**: empty → *"Enter your email address."*; invalid (regex `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`) → *"Check your email — it looks incomplete."*. Error shown inline under field with warning icon; field gets red ring; error clears on edit.
- **Footer**: *"Already have an account?"* + **Sign In** button; *"By continuing you agree to the Terms and Privacy Policy."*
- **Exits**: Apple/Google/Sign In → SETUP_PROFILE (prototype; real: existing accounts skip setup); valid email → AUTH_CHECK_EMAIL.

#### 2.5.3 AUTH_CHECK_EMAIL
- Back → AUTH_SIGNUP. Envelope icon; *"Check Your Email"*; *"We sent a sign-in link to **{email}**. It expires in 15 minutes."*
- Buttons: *Open Mail* (opens Mail app; magic link returns via Universal Link → SETUP_PROFILE), *Resend Link* (toast *Link Sent*).

#### 2.5.4 SETUP_PROFILE
- Nav title *"Your Profile"*, progress 33%. Header *"About You"* / *"This fills in your cards. You can change it anytime."*
- **Add Photo** (avatar picker; initials fallback).
- Grouped form: Name (*Full name*), Job Title (*e.g. Product Designer*), Company (*Company*), Phone (*+998*, tel), Email (*you@company.uz*, email).
- Footer *"Name and email came from your Apple ID. Each card decides what it shows."* (prefill from SIWA/Google).
- CTA *Continue* — requires Name (toast *Add your name to continue*) → SETUP_PERMISSIONS.

#### 2.5.5 SETUP_PERMISSIONS
- Nav *"Permissions"*, progress 66%, **Back** (→ profile) and **Skip** (→ finish). Header *"Allow Access"* / *"Cardy only uses these when you connect or scan. Change them anytime in Settings."*
- Rows (icon, title, subtitle, button **Allow** / **✓ Allowed** / **Off**):
  | Key | Title | Subtitle | System prompt title / message |
  |---|---|---|---|
  | mic | Microphone | Add notes by voice | *"“Cardy” Would Like to Access the Microphone"* / *"Cardy turns your voice notes into text. Audio isn’t stored."* |
  | notif | Notifications | Know when someone wants to connect | *"“Cardy” Would Like to Send You Notifications"* / *"Notifications may include alerts, sounds and icon badges."* |
  | camera | Camera | Scan other people’s cards | *"“Cardy” Would Like to Access the Camera"* / *"Cardy uses the camera to scan business card QR codes."* |
  | network | Nearby Devices | Connect with people around you | *"“Cardy” Would Like to Find Devices on Your Local Network"* / *"Cardy uses your local network to connect with people nearby."* |
- Tapping **Off** row → ALERT *"Turn On in Settings"* / *"Open iOS Settings › Cardy to allow {title}."* [Cancel, Open Settings].
- Camera denied propagates to SCAN denied state.
- CTA *Create My First Card* (and Skip) → HOME + CARD_CREATE opened.

#### 2.5.6 DEFERRED_WELCOME
- Shown on first launch when the install originated from a web card page.
- Owner's card (tilted), eyebrow *"Welcome to Cardy"*, title *"You met {owner full name} at {event}. Connect?"*, body *"{owner first} is already in your People. Connecting shares your card back."*
- *Connect* → PEOPLE tab, toast *Connected with {first}*. *Not Now* → HOME.
- Implies: the owner is pre-inserted in the new user's People; Connect sends the new user's card back to the owner. (New user still needs account + card — see §9 Q22.)

#### 2.5.7 HOME
- **Header**: large title *"Hi, {first name}"*; avatar button (photo or initials) → PROFILE tab.
- **Offline banner** (when offline): wifi-slash icon, *"You're offline. Your QR code still works."*
- **Event row** (one of):
  - Active event banner: green dot, event name, *"{N} new connection(s)"*, chevron → EVENT_DETAIL. (No inline End button — deliberately removed in v7.)
  - No active event: button row with calendar-plus icon *"Start Event"* / *"Everyone you meet is tagged automatically"* → START_EVENT (Free: if an event is active → ALERT_ONE_EVENT).
- **Follow Up Today** section (*"Follow Up Today"*, **See All** → FOLLOWUPS):
  - Up to 3 open reminders with due ≤ today (overdue + today), sorted by due.
  - Card: initials avatar, *what* (bold), *"{name} · {due}"* (due red if overdue, tint if today); tap → REMINDER_EDIT.
  - Buttons: primary channel action (*Telegram* / *Mail* / *Call* with icon → opens external app; toast *Opening {channel}*), **Snooze ▾** (MENU_SNOOZE: Tomorrow / In 3 Days / Next Week / Custom… → REMINDER_EDIT), **Done** (toast *Marked Done* + Undo).
  - Empty: *"Nothing due today. {N} coming up."* or (no reminders at all) *"No follow-ups yet. Add one right after you connect — it takes 2 seconds."*
- **My Cards** section (*"My Cards"*, **+ New Card** → CARD_CREATE; Free with ≥2 cards → ALERT_CARD_LIMIT):
  - Horizontal snap carousel; each tile: card thumbnail (tap → QR_FULLSCREEN; long-press 480 ms → CARD_PREVIEW_MENU), card name, **…** (MENU_CARD_ACTIONS), stats line *"Viewed 14 · Saved 9 · Shared back 5"*, **Show QR** (→ QR_FULLSCREEN), share icon (→ SHARE_SHEET).
  - Scrolling sets the "active card". Page dots shown only when >1 card. (Duplicate "New Card" tile removed in v7.)
- **Recent** section (*"Recent"*, **See All** → PEOPLE): first 3 connections (initials, name, *"{event} · {city}"*, relative time e.g. *2d*, *now*, *1mo*) → CONNECTION_DETAIL.
  - Empty: *"People you connect with show up here. Open Connect at your next event."*
- **States**: offline; event active/inactive; empty demo data (no follow-ups, no recent); Free limits.

#### 2.5.8 SCAN
- Dark camera screen. Title *"Scan Card"*. Segmented **QR Code | Paper Card**. Event pill (green dot + event name) if event active.
- Viewfinder with corner brackets + animated scan line. QR frame 250×250; Paper frame 310×200 (card ratio).
- Hint pill: QR *"Point at a Cardy or vCard QR code"*; Paper *"Fit the business card inside the frame"*.
- Bottom controls: **Paste Link** (clipboard; → SCANNED_CARD), **Shutter** (Paper mode only → PAPER_REVIEW), **Flashlight** toggle (toast *Torch On*).
- **Results**:
  - Cardy link QR → SCANNED_CARD.
  - vCard QR → (not specified; presumably ADD_CONTEXT/contact save — §9 Q41).
  - Other QR → ALERT_INVALID_QR: *"No Business Card Found"* / *"This QR code opens {domain}. It isn’t a Cardy or vCard code."* [Cancel, Open in Safari].
  - Paper OCR fails → ALERT_PAPER_NOT_READ: *"Couldn’t Read the Card"* / *"Hold the card flat in good light, or type the details yourself."* [Enter Manually → PAPER_REVIEW with empty fields, Retake].
- **Camera denied state** (full overlay): camera-slash icon, *"Camera Access Needed"*, *"Allow camera access in Settings to scan cards. You can still paste a link."*, *Open Settings*, *Paste Link*.

#### 2.5.9 SCANNED_CARD (push from Scan)
- Nav back *"Scan"*, title *"Scanned Card"*.
- Their card face (rendered with their design; only fields visible to non-connections), name, *"{title} · {company}"*, field list (label + tinted value).
- Footer *"Connect to see what {first} shares with connections only."*
- Buttons: **Connect** (person-plus) → CONNECTED (prototype jumps straight to match; see §9 Q8); **Add to Contacts** → saves to iOS Contacts + opens ADD_CONTEXT (kind "Added to Contacts").

#### 2.5.10 PAPER_REVIEW (push)
- Nav: **Retake** (→ SCAN paper mode), title *"Paper Card"*, **Save**.
- Captured image preview with badge *"{N} fields found"*.
- **Detected Details** (editable rows with icons): Name, Title, Company, Phone, Email, Telegram. Footer *"Read on your iPhone. Check the details before saving."* (on-device OCR).
- Then the shared **Context Capture block** (§3.14): Where You Met (Auto), Private Note (+ mic, tags), Follow Up.
- Bottom CTA *Save Contact*. Save → creates connection (`via: paper`) → CONNECTION_DETAIL; toast *Saved · Reminder Set* or *Contact Saved*.

#### 2.5.11 PEOPLE
- **Nav**: collapsing large title *"People"* + count; right button **Connect** (person-plus icon) → CONNECT.
- **Search** field (*Search*), clear button; matches name, company, event, city.
- **Segmented filter**: *All | Events | Places*.
- **Requests** section (if pending): *"{first} wants to connect"*, *"{company} · {event}"*, **Accept** (adds connection, toast *Connected with {first}*), **Decline** (ALERT *"Decline {first}’s Request?"* / *"They won’t be notified."* [Cancel, Decline]). Footer *"Accepting shares your Work card."* (= default card).
- **Loading**: skeleton list (5 rows).
- **All**: one group *"All People"* + count. **Places**: groups by city. **Events**: event cards instead of rows — name, *"{place} · {dates}"*, *In progress* badge (green dot) for active event, face pile (≤4 initials), *"{N} people · {N} notes · {N} follow-ups"* → EVENT_DETAIL.
- **Row**: initials avatar, name (ellipsized), **"via web"** badge (globe) for share-backs, subtitle *"{title} · {meta}"* where meta = *"via qr · "/"via paper · "* prefix (if source qr/paper) + event (All) / *"{city}, {date}"* (Events) / *"{event}, {date}"* (Places); chevron.
  - Tap → CONNECTION_DETAIL; **exception**: a web share-back with no note → ADD_CONTEXT (kind web).
  - **Swipe left** reveals **Note** (orange) and **Remove** (red). Note → CONNECTION_DETAIL in note-edit mode. Remove → ALERT_REMOVE.
  - **Long-press** → MENU_PERSON_ROW: *Open*, *Add Note*, *Remove* (destructive).
  - Remove confirm → toast *Connection Removed* with **Undo** (4 s).
- Hint footer *"Swipe left or touch and hold a person for more actions."*
- **Empty** (no connections, no requests): users-three icon, *"No Connections Yet"*, *"Scan someone's card or open Connect. Your notes about them stay private."*, *Open Connect* → CONNECT.
- **No results**: *"No Results for “{q}”"* / *"Check the spelling or try a new search."*

#### 2.5.12 CONNECTION_DETAIL (push)
- **Nav**: back *"People"*; right **Edit Note** → edit mode (nav becomes **Cancel** / **Done**); title appears on scroll.
- **Header**: 96pt avatar (initials), name, *"{title} · {company}"*.
- **Action grid (4)**: message, call, mail, save (save → *Added to Contacts*; others open external apps).
- **Note · 🔒 Only You** section:
  - View: Event, Place (*"{place}, {city}"*), Met (date); **Merged** row (git-merge icon) *"Your QR note + their web share-back"* if merged; note text or **Add Note…**; tag chips.
  - Edit: Event, Place, Tags (*Comma separated*), multiline *"What did you talk about?"*. Done → toast *Note Saved*.
- **Follow Up** section: existing open reminder row (bell icon, *what*, *"{due} · {channel}"*, **Done** button → *Marked Done* + Undo; row tap → REMINDER_EDIT); chips *Tomorrow / In 3 days / Next week / Pick a date* (selected chip reflects current due; tapping sets/reschedules → toast *Reminder: {due}*; Pick a date → REMINDER_EDIT). Footer *"Tap a day to reschedule."* (has reminder) / *"Pick a day. Cardy reminds you with your note."*. Free limit check when creating.
- **Earlier Meetings** (if any): event, *"{place} · {date}"* rows.
- **"What did we talk about?"** (sparkle; PRO badge on Free) → AI_INSIGHT (recap).
- **Shared Card**: their card face + field list (label, tinted value — tappable presumably). Footer *"You shared your Work card with {first}."*
- **Danger group**: *Remove Connection* (ALERT_REMOVE → back to People, toast *Connection Removed*), *Block {first}* (ALERT *"Block {first}?"* / *"Your cards will look like they don’t exist to them."* → toast *Blocked*).

#### 2.5.13 PROFILE
- Large title *"Profile"*.
- **Profile header**: avatar with camera badge (photo picker), inline-editable **Name** and **Job Title**.
- **Contact Details** (*"Contact Details"*): rows Phone / Email / Telegram / Website / LinkedIn — colored icon, label, inline-editable value, privacy pull-down (MENU_FIELD_PRIVACY: *Public* "Anyone with your link" / *Connections* "People you’ve connected with" / *Private* "Only you"). Footer *"Public: anyone with your link. Connections: people you've connected with. Private: only you."*
- **Cards**: rows with mini card, name, link *cardy.link/c/{slug}*, *Default* label, up-down chevron → MENU_CARD_ACTIONS.
- **Settings**: *Appearance* (Dark / Light menu), *Language* (English / Oʻzbekcha / Русский menu), *Pause All Links* toggle (toast *Links Paused* / *Links Resumed*). Footer *"Paused links show an inactive page. Printed QR codes work again when you resume."*
- Group: *Widgets* → WIDGETS_GALLERY; *Preview Public Page* → web page.
- Group: *Cardy Pro* — value *Free* (should reflect plan) → SETTINGS_SUBSCRIPTION.
- Group: *Notifications*, *Privacy & Data*, *Help & Support*.
- *Sign Out* (red) → ALERT *"Sign Out?"* / *"You can sign back in with Apple, Google or email."* [Cancel, Sign Out] → ONB_WELCOME.
- Note: Company is NOT editable here in v8 (only in setup) — §9 Q3. Follow-ups/Events rows were removed from Profile in v7.

#### 2.5.14 FOLLOWUPS (push)
- Nav back *Home* or *Profile* (origin), title *"Follow-ups"*, **+** (*New reminder*) → REMINDER_EDIT (Free limit check).
- Groups with counts: **Overdue** (red header), **Today**, **This Week** (1–6 days), **Later** (≥7), **Done**.
- Row: initials, *what* (strikethrough + secondary if done), *"{name} · {event or company}"*, due label (red overdue, tint today). Tap → REMINDER_EDIT.
- **Swipe left**: **Snooze** (orange, +1 day from max(due, today)) and **Done** (green; label *Undo* for done items). Toasts *Snoozed to {date}* / *Marked Done* / *Moved Back*, each with Undo.
- **Long-press** → MENU_REMINDER_ROW: *Edit…*, *Open Contact*, *Snooze*, *Done*/*Undo*, *Delete* (destructive, immediate).
- Footer hint *"Swipe left on a reminder to snooze it or mark it done."*
- **Empty**: bell icon, *"No Follow-ups Yet"*, *"Add one right after you connect — it takes 2 seconds."*
- Due label format: *Today*, *Tomorrow*, *Yesterday*, else *"{Weekday}, {Mon} {d}"* e.g. *"Tue, Sep 29"*.

#### 2.5.15 EVENT_DETAIL (push)
- Nav back *Home* or *People* (origin); **Edit** (only for the current/most recent event) → START_EVENT (edit mode).
- Title event name; *"{place} · {dates}"*; if active: *"In progress · new connections are added automatically"* (green dot).
- **Stats tiles (3)**: People, With notes, Follow-ups.
- **Follow Up with Everyone I Haven’t Yet ({N})** (shown if any person lacks an open reminder) → creates reminder *"Follow up from {event}"* due tomorrow for each (channel = telegram if available else email else call); toast *"{N} reminders set for tomorrow"*.
- **People You Met** list: name, note or *"No note yet"*, status pill (due label tinted / red overdue / *Done* / *None*) → CONNECTION_DETAIL.
- **AI row**: *Pre-event Briefing* (active) or *Event Recap* (ended) with PRO badge on Free → AI_INSIGHT. **Resume Event** row if the event ended (toast *Event Resumed*).
- **Export to CSV or CRM** (PRO badge on Free) → EVENT_EXPORT. **End Event** (red, only active) → ALERT *"End {event}?"* / *"New connections won’t be added to it. You’ll get a summary."* [Cancel, End Event] → EVENT_ENDED.

#### 2.5.16 WIDGETS_GALLERY (push) — also defines the widget extension
Informational page showing available widgets (rendered with the default card's palette as wallpaper):
- **Follow-ups (medium)** — header *"Follow Up Today"* + count of open due ≤ today; 2 rows (initials, what, *"{name} · {due}"*). Footer *"Medium widget. Tap a reminder to open it in Cardy."* → `WIDGET_FOLLOWUPS_M`.
- **Lock Screen** — rectangular: QR + *"Scan to connect"* + owner name (`WIDGET_LOCK_QR_RECT`); circular QR glyph (`WIDGET_LOCK_QR_CIRC`). Footer *"Tap the widget to show your QR at full brightness, without unlocking."*
- **Home Screen** — Small: QR + *"{Card} Card"* — *"Your QR, one tap away."* (`WIDGET_QR_S`); Medium: card face + *"{Card} Card"*, *"{N} new connections this week"*, *Show QR* (`WIDGET_CARD_M`).
- Footer *"Touch and hold the Home Screen, tap Edit › Add Widget, then choose Cardy."*

#### 2.5.17 SETTINGS_NOTIFICATIONS (push)
- If iOS notification permission denied: intro (red bell-slash) *"Notifications Are Off"* / *"Notifications are turned off for Cardy in iOS Settings. You won’t hear about connect requests."* + action *Open iOS Settings*.
- **Reminders**: toggle *Follow-up Reminders* (*"On the day you picked, with the reason"*, default on); toggle *Event Summary* (*"When an event ends: who you met and what’s left"*, on).
- **Deliver Reminders Via** (checkmark list): *Push Notifications* (default) / *Telegram Bot* (sub *"Connected · @CardyRemindBot"* or *"Not connected"*). Choosing Telegram when not linked → ALERT *"Connect Telegram Bot"* / *"Open @CardyRemindBot and tap Start. Reminders arrive in the chat with a link to reply."* [Cancel, Open Telegram → linked, toast *Telegram Connected*]. Footer *"The bot sends each reminder with a one-tap link to the chat."*
- **Activity**: *Connect Requests* (*"When someone nearby wants your card"*, on), *Card Saved* (*"When someone adds you to Contacts"*, on), *Weekly Summary* (*"New connections and card views"*, off). Footer *"Summaries arrive quietly, without sound."*
- **From Cardy**: *Product News* (off).

#### 2.5.18 SETTINGS_PRIVACY (push)
- **Discovery**: *Find Me by Email* (*"People with your email can send a connect request"*, on); *Show in Nearby* (*"Appear in Connect for people around you"*, on).
- **Your Data**: *Share Usage Analytics* (on); *Download My Data* (toast *Link sent to your email*); *Blocked People* (value count, e.g. 0 → list, not designed). Footer *"Cardy never sells your data. Notes you write are only visible to you."*
- *Delete Account* (red) → SETTINGS_DELETE_ACCOUNT.

#### 2.5.19 SETTINGS_SUBSCRIPTION (push)
- **Plan** (info rows): Current Plan (*Free* / *"Pro · Yearly|Monthly"*), Cards (*"{n} of 2"* / *"{n} · Unlimited"*), AI Designs (*"{n} of 3 left"* / *"30 a month"*), Renews (date, Pro only).
- Free: *Upgrade to Cardy Pro* → PAYWALL. Pro: *Change Plan* → PAYWALL; *Cancel Subscription* (red) → ALERT *"Cancel Cardy Pro?"* / *"You keep Pro until the end of this billing period. Cards beyond two become read-only after that."* [Keep Pro, Cancel] (real impl: App Store manage subscriptions — §9 Q27).
- *Restore Purchases* (toast *Purchases Restored* / *No purchases to restore*). Footer *"Subscriptions are billed through your Apple ID. Cancel at least 24 hours before renewal."*

#### 2.5.20 SETTINGS_HELP (push)
- **Help**: *How Cardy Works*, *Printing Your QR Code*, *Contact Support* (value *support@cardy.app* → Mail).
- **About**: *Version* (*1.0 (42)*), *Terms of Service*, *Privacy Policy*, *Rate Cardy* (App Store).

#### 2.5.21 SETTINGS_DELETE_ACCOUNT (push, back *"Privacy"*)
- Intro (red warning) *"Delete Your Account?"* / *"This permanently deletes your profile, {n} cards with their links and QR codes, and your notes on {n} people. Printed QR codes will show an inactive page."*
- *Download My Data First* (toast *Link sent to your email*). Footer *"You’ll get an email with a copy of everything."*
- *Delete Account* (red) → ALERT *"Delete Account?"* / *"This can’t be undone."* [Cancel, Delete] → ONB_WELCOME + toast *Account Deleted*. Pro footer: *"Deleting your account doesn’t cancel Cardy Pro. Cancel it in Subscription first."*

#### 2.5.22 CARD_SETTINGS (push, title *"{Name} Card"*, back *Profile*)
- **Card**: *Name* (inline input, right-aligned), *Link* (info *cardy.link/c/{slug}*), *Default Card* toggle (*"Used for Connect, events and widgets"*; turning off the current default → toast *Pick another card as default*).
- **Order** (only if >1 card): *Move Up* / *Move Down* (disabled at ends). Footer *"Order on Home."*
- *Edit Design* → CARD_EDITOR; *Duplicate Card* (Free with ≥2 cards → ALERT *"Card Limit Reached"* / *"The Free plan includes 2 cards. Upgrade to Cardy Pro to duplicate this one."* [Not Now, See Pro]; else creates *"{name} Copy"* with new slug, toast *Card Duplicated*).
- *Delete Card* (red) → ALERT_DELETE_CARD → back, toast *Card Deleted*. Cannot delete last card (toast *You need at least one card*); deleting default promotes first remaining card.

#### 2.5.23 CARD_CREATE (cover wizard)
Header: back/cancel button (left), step title (center), progress bar. Bottom CTA on most steps.

| Step | Title | Progress | Content | CTA |
|---|---|---|---|---|
| method | *New Card* | 20% | *"How do you want to start?"* / *"You can change everything later in the editor."* Options: **Start from a Template** (*"Nine layouts, ready for your details"*), **Design with AI** (*"Answer three questions, get three designs"*, Free badge *"{n} left"*), **Blank Card** (*"A minimal layout to build on"*). Left button *Cancel*. | (none) |
| gallery | *Templates* | 45% | 2-column grid of the 9 templates rendered with user data; selected ring + check; Editorial shows *PRO* tag → PAYWALL on Free. | *Continue* → details |
| ai | *Design with AI* | 45% | Q1 *What is it for?* Conference / Client meetings / Freelance / Personal; Q2 *Style* Minimal / Professional / Bold / Creative; Q3 *Card Appearance* Dark / Light (checkmark lists). Footer quota *"{n} of 3 AI designs left this month."* / *"Cardy Pro includes 30 AI designs a month."* | *Generate 3 Designs* (Free with 0 left → PAYWALL) |
| gen | *Design with AI* | 65% | Spinner, *"Designing your card…"*, *"Matching layouts and palettes to “{use}”."* (no back) | — |
| results | *Pick a Design* | 70% | 3 full-size previews, selectable. Footer *"Suggestions use Free palettes only, so every design can be published."* (Free) / *"Tap a design to select it."* | *Use This Design* → details |
| details | *Details* | 88% | Live preview; *Card Name* input (default from Q1: Conference/Client/Freelance/Personal; default "Conference"); **Show on This Card** toggles per field (private fields disabled: *"Private — hidden from all cards"*, tap → toast *Change privacy in Profile first*). Footer *"Values come from your profile. Change privacy there."* | *Publish Card* |
| done | (none) | 100% | Check icon, *"Your Card Is Live"*, link *cardy.link/c/{slug}*, card preview. | *Done* (→ HOME, toast *Card Published*), *Share Now* (→ HOME + SHARE_SHEET) |

- Back mapping: gallery→method, ai→method, results→ai, details→(gallery|results|method by origin); method Cancel closes.
- Publish failure → ALERT *"Couldn’t Publish Card"* / *"Check your connection. Your card is saved as a draft and will publish when you’re back online."* [OK] → implies offline draft + publish queue.
- AI design mapping (prototype heuristic; real impl via AI service): style → templates — minimal: minimal, stack, terminal; professional: professional, modern, minimal; bold: bold, split, gradient; creative: editorial, gradient, split (Free: gradient, split, stack). Palettes Free: ink, sand, graphite; Pro: ocean, ember, ink. Stack uses rounded font; use=personal → density minimal. A generation consumes 1 quota.
- New card slug: `{firstname}-{4 chars}`.

#### 2.5.24 CARD_EDITOR (cover)
- Nav: *Cancel* / *"{Name} Card"* / *Done* (→ toast *"{Name} Card Published"*; republishes web page).
- Live card preview at top; segmented **Template | Color | Type | Fields | Media**.
- **Template**: 3-col grid of 9 templates (selected ring + check; lock icon on Editorial for Free → ALERT *"Editorial Is a Pro Template"* / *"Upgrade to Cardy Pro to use Editorial and every palette."* [Not Now, See Pro]).
- **Color**: *Palette* — 6 swatches (Graphite, Snow, Ink, Sand, Ocean🔒, Ember🔒; locked → PAYWALL); footer *"{Palette}. Text contrast meets WCAG AA."*; *Card Appearance* segmented Light | Dark; *Gradient Background* toggle (Gradient template forces on: toast *Gradient template is always gradient*).
- **Type**: *Typeface* grid "Aa" — Default (system), Rounded, Serif, Mono; footer for Terminal/Editorial *"This template sets its own typeface."*; *Alignment* Leading | Center; *Density* Minimal | Balanced | Detailed (max 2 / 3 / 5 contact lines).
- **Fields**: *Show on This Card* toggles; subtitle *"{value} · {privacy}"*; private disabled (*"Private — hidden from all cards"*). Footer *"Values come from your profile. Private fields never appear on a card."*
- **Media**: *Photo* — *Choose Photo…*, *Show on Card* toggle, footer *"Shows on Modern, Split and Stack."*; *Logo* — *Choose Logo…*, *Show on Card*, footer *"Shows on Professional."*; *QR Code* toggle, footer *"Always black on a white plate. Logos never go on the code."* (Photo is profile-level, shared by all cards; logo also profile-level.)
- Prototype applies edits live (Cancel does not revert) — §9 Q12.

#### 2.5.25 CARD_EXPORT (cover)
- Nav *Cancel* / *Export*. Preview area per format. Segmented **PNG | PDF | Wallet | Lock Screen**.
- Options list (checkmark), header per format:
  | Format | Header | Options |
  |---|---|---|
  | PNG | Resolution | 1× *1020 × 660 px*; 2× *2040 × 1320 px · Retina* (default); 3× *3060 × 1980 px · Print-ready* |
  | PDF | Page | *Single Card* — *85 × 55 mm, 3 mm bleed, crop marks*; *A4 Sheet* — *10 cards up, for a print shop* |
  | Wallet | Pass | *Apple Wallet* — *QR on the pass, updates when you edit* |
  | Lock Screen | Device | *iPhone 16 Pro* *1206 × 2622 px*; *iPhone SE* *750 × 1334 px* |
- Footer *"The QR keeps a 4-module quiet zone and error correction level M in every format."*
- Wallet preview: Cardy logo, card name, Name, Title, Company, QR. Lock preview: date/time + QR on palette gradient.
- Buttons: *Share* (→ SHARE_SHEET), primary *Save to Photos* / *Save to Files* / *Add to Wallet* / *Save Wallpaper* → toasts *Saved to Photos* / *Saved to Files* / *Added to Wallet* / *Wallpaper Saved*.

#### 2.5.26 CONNECT (cover; "Exchange")
- Nav title *"Connect"*, *Done*.
- Segmented **Nearby | Tap Phones**. Event pill if active.
- **Nearby**: pulsing rings around own avatar; *"Looking for people nearby"* / *"Connect with other Cardy users around you. You send your card and get theirs back. To share with someone without the app, use Show QR."*
- **Tap Phones**: two-phones bump animation; *"Hold phones together"* / *"Hold the top of your iPhone near theirs. Cardy needs to be open on both phones."*
- Card chooser segmented (cards by name) — which card is sent.
- **Notice banner** (dismissable): declined *"Kamila declined your request."*; timeout *"Sardor didn’t respond. They may have closed Connect."*
- **Empty** (Nearby only): *"No One Nearby Yet"* / *"Ask them to open Connect in Cardy, or show your QR code instead."* + *Show QR*.
- **Nearby on Cardy** list: avatar, name, *"{title} · {company}"*, button *Connect* → *Waiting…* (one request at a time) → accepted → CONNECTED; declined → notice; no response → notice.
- **INCOMING_REQUEST** overlay (bottom card): their card face, name, *"wants to connect with you"*, *Decline* (toast *Request Declined*) / *Accept* (→ CONNECTED), footer *"You’ll share your {card} card."*

#### 2.5.27 CONNECTED (cover; "You're Connected")
- Nav *Not Now* (adds the connection without context → PEOPLE) / *Save*.
- Both cards overlapped (mine + theirs). *"You're Connected"* / *"You and {first} are connected. Add context while it's fresh."*
- Context Capture block (§3.14): Where You Met (Auto) + Private Note + Follow Up.
- *Add to Contacts* row (toast *Added to Contacts*).
- Save → commit → CONNECTION_DETAIL; toast *Saved · Reminder Set* / *Connection Saved*.

#### 2.5.28 QR_FULLSCREEN (cover)
- Top: *"Brightness raised"* (sun icon) indicator; *Done*.
- Owner name, *"{title} · {company}"*. Large QR on white rounded plate. Paused: QR dimmed (10%) + *"Link Paused"* overlay.
- *"Scan with the camera — no app needed"* + link (*cardy.link/c/{slug}*; offline: *"Contact only · works offline"*).
- Card chooser segmented.
- **Offline QR** toggle; footer *"Works without internet. Contact only, no analytics or Connect."* (encodes a vCard instead of URL).
- Buttons: *Connect Nearby* → CONNECT; *Share* → SHARE_SHEET.
- On close: if QR was visible > 2 s → JUST_MET sheet.

#### 2.5.29 SHARE_SHEET (sheet)
- Grabber; header: mini card, *"{name} · {card}"*, link, close ✕.
- Targets row: AirDrop, Messages, Telegram, WhatsApp, Mail (toast *Sent via {target}*).
- Actions: *Copy Link* (toast *Link Copied*), *Add to Apple Wallet* (→ CARD_EXPORT wallet), *Save Image or PDF* (→ CARD_EXPORT png).
- *Pause This Link* toggle (prototype shares state with global "Pause All Links" — §9 Q5).
- After a share action, dismissing → JUST_MET.

#### 2.5.30 START_EVENT (sheet; new / edit)
- Nav *Cancel* / *"Start Event"* or *"Edit Event"* / *Start* or *Save*.
- **From Your Calendar** chips (e.g. *"Tashkent Tech Week · Today"*, *"Product Meetup · Fri"*) → fill name, place, dates.
- Fields: *Name* (*Event name*), *Place* (*Where is it?*), *Dates* (display e.g. *"Sep 24 – 26"*, map-pin icon; picker UI undefined — §9 Q16).
- **Card to Share** segmented (cards). Footer *"Everyone you connect with is added to this event — by QR, Nearby, Tap Phones, your web page or a paper card. It ends by itself after the last day and sends you a summary."*
- Validation toast *Add an event name*. Toasts *Event Started* / *Event Updated* (edit renames the event on all its connections).
- Free & an event already active → ALERT *"One Active Event on Free"* / *"End {event} first, or upgrade to run several events at once."* [Not Now, Upgrade].

#### 2.5.31 EVENT_ENDED (cover)
- Flag icon, *"{event} Ended"*, summary *"You met {N} people. {N} have notes. {N} follow-ups are scheduled."*
- Stats tiles (People / With notes / Follow-ups). *Export to CSV or CRM* (PRO).
- **No Note Yet** list (≤4): name + *Add Note* → CONNECTION_DETAIL in edit-note mode.
- Buttons: *Add Notes While You Remember* → EVENT_DETAIL; *Done* → HOME.

#### 2.5.32 ADD_CONTEXT (large sheet)
- Nav *Skip* / *"Add Context"* / *Save*.
- Person header: initials, name, kind label — *"Shared via your web page"* (globe, tint) or *"Added to Contacts"* (green check).
- Context Capture block (§3.14). Save → commit; toast *Saved · Reminder Set* / *Context Saved*.

#### 2.5.33 JUST_MET (sheet; "Who did you just meet?")
- Nav *Skip* / *"Who did you just meet?"* / *Save* (disabled until Name).
- Fields: *Name* (*Their name*), *Note* (*One line to remember them*) + mic (listening row *"Listening… tap the mic to stop"*).
- Follow Up chips: Tomorrow / In 3 days / Next week (toggle).
- Footer *"If they share their contact from your page later, Cardy merges the two."*
- Save → creates connection (title *"Met via your QR"*, `via: qr`, `pendingMerge: true`, event/place from active event) and optional reminder (*"Follow up"*, telegram, 10:00). Toast *Saved · Reminder Set* or *Saved {first}*.

#### 2.5.34 REMINDER_EDIT (large sheet)
- Nav *Cancel* / *"New Reminder"* or *"Edit Reminder"* / *Save*.
- Person: row with initials + name (+ *Change* for new reminders → MENU_PERSON_PICKER) or *Choose a Person* button.
- **Reminder**: *To do* (placeholder *Send deck*; default "Follow up").
- **When**: chips Tomorrow / In 3 days / Next week; *Date* picker (min today); *Time* picker (default 10:00). Footer summary *"Cardy will remind you {tomorrow | on Tue, Sep 29} at {10:00}."*
- **Reply Via**: segmented Telegram | Email | Call. Footer *"Only you see your reminders. The other person is never notified."*
- Edit mode extras: *Open Contact*; *Delete Reminder* (ALERT *"Delete Reminder?"* / *"You won’t be reminded to follow up with {first}."* → toast *Reminder Deleted*).
- Save: no person → toast *Choose a person first*; new + Free limit → ALERT_FU_LIMIT; toasts *Reminder Set* / *Reminder Updated*.

#### 2.5.35 AI_INSIGHT (sheet)
- Header: sparkle icon, title, subtitle, close ✕. Lines list (icon + text). Footer.
- **Recap** (per person): title *"What did I talk about with {first}?"*, sub *"AI recap from your private notes"*. Lines: 📍 *"Met at {event}, {place} on {date}."*; ⏱ *"Earlier: {event}, {date}."* (per earlier meeting); 💬 *"You talked about: {note}"* or *"No note yet. Add one so the recap has more to go on."*; 🔔 *"You promised: {what}, due {due}."* or *"No follow-up set."*; 💡 *"Open with: “Great to meet you at {event}. Here’s the {thing} I mentioned.”"*
- **Briefing / Recap** (per event): title *"Briefing · {event}"* (active) / *"Recap · {event}"*; sub *"{place} · {dates}"* or *"From your notes"*. Lines: *"You’ve met {N} people here: A, B, C and others."*; *"Open promises: {first} — {what}; …"* / *"No open promises."*; *"{N} people have no note yet: …"* / *"Everyone has a note."*; tip *"You’re sharing your {card} card here — it shows your job title and company."* (active) / *"Send the follow-ups while the event is still fresh."*
- Footer: Free *"AI recaps are part of Cardy Pro. 3 free recaps left this month."*; Pro *"Made only from your private notes. Nothing is shared."*

#### 2.5.36 EVENT_EXPORT (large sheet)
- Nav *Cancel* / *Export*. Title = event name; *"{N} people · notes and follow-ups included"*.
- **Format** (checkmark list): CSV File, Google Sheets, HubSpot, amoCRM, Bitrix24.
- **Included** chips: Name, Title, Company, Phone, Email, Telegram, Event, Place, Date met, Note, Tags, Follow-up. Footer *"Private notes are included only in your export. Nothing is sent to the people you met."*
- CTA Free *Upgrade to Export* (→ PAYWALL) / Pro *"Export {N} Contacts"* → toasts *Saved to Files* / *Opened in Google Sheets* / *Sent to HubSpot* / *Sent to amoCRM* / *Sent to Bitrix24*.

#### 2.5.37 PAYWALL (cover)
- Close ✕ (returns to origin route).
- Hero card: event *"Tashkent Tech Week"*, *"{N} people · {N} follow-ups"*, 3 reminder rows (initials, what, first name, due), AI recap sample *"**AI recap.** You talked with Jasur about the Payline SDK and promised a design review in October."* (uses the user's real data where available).
- *"Cardy Pro"* / *"Remember everyone you meet and follow up on time."*
- Features: *Unlimited follow-up reminders* (*Free: 5 active*); *Unlimited events with summaries* (*Free: 1 active event*); *AI recap* (*“What did I talk about with Jasur?” and pre-event briefings*); *Export events to CSV or CRM* (*Every connection, note and follow-up*); *All templates and palettes* (*Editorial, Ocean, Ember and more*).
- Plans (radio): **Yearly $19.99** — *$1.67 a month, billed yearly* — badge *Save 44%* (default); **Monthly $2.99** — *Billed monthly*.
- Terms text: *"$19.99 a year. Renews automatically until canceled. Cancel anytime in Settings at least 24 hours before renewal."* (monthly: *"$2.99 a month. …"*).
- CTA *Subscribe* (Pro: *You’re on Pro*) → toast *Welcome to Cardy Pro*, return to origin. Links: *Restore Purchases* (toast *No purchases to restore*), *Terms of Use*, *Privacy Policy*.

### 2.6 Menus and context menus

| ID | Trigger | Items |
|---|---|---|
| MENU_CARD_ACTIONS / CARD_PREVIEW_MENU | Home card "…", Profile Cards row, long-press card thumbnail (preview variant shows the large card above the menu) | Copy Link (*Link Copied*) · Share… · Show QR Code · Connect Nearby · Edit Card · Card Settings… · Export… · *Set as Default* / ✓*Default Card* (toast *"{name} is your default"*) · Delete Card (destructive → ALERT_DELETE_CARD) |
| MENU_FIELD_PRIVACY | Profile field privacy button | ✓ Public (*Anyone with your link*) · Connections (*People you’ve connected with*) · Private (*Only you*) |
| MENU_APPEARANCE | Profile → Appearance | Dark · Light |
| MENU_LANGUAGE | Profile → Language | English · Oʻzbekcha · Русский |
| MENU_SNOOZE | Home follow-up "Snooze ▾" | Tomorrow · In 3 Days · Next Week · Custom… (→ REMINDER_EDIT). Base = max(due, today). Toast *Snoozed to {date}* + Undo |
| MENU_PERSON_PICKER | REMINDER_EDIT person | Recent connections (name + event/company subtitle), checkmark current |
| MENU_PERSON_ROW | Long-press People row | Open · Add Note · Remove (destructive) |
| MENU_REMINDER_ROW | Long-press follow-up row | Edit… · Open Contact · Snooze · Done/Undo · Delete (destructive) |

### 2.7 Web surfaces (separate web deliverable; specified in plan.md "Section 7")

Public card page `cardy.link/c/{slug}` (light, iOS-like). Shows **only Public fields** included in that card's visible fields.

| ID | Description |
|---|---|
| WEB_CARD | Card face; name; *"{title} · {company}"*; field rows (lowercase label + value; **copy** button on phone & email → *Phone Copied* / *Email Copied*); buttons *Save to Contacts* (primary), *Message on Telegram* (if Telegram public), *Exchange Contacts with {first}* (until shared) → WEB_SHAREBACK_SHEET. After save: soft CTA *"Want a card like this?"* / *"Free, 30 seconds."* / *Get Cardy* (→ App Store / deferred link). Footer *"Made with Cardy · Only public details are shown"*. |
| Platform: **iOS Safari** (`ios`) | Smart App Banner (*Cardy* / *Remember everyone you meet* / *GET — On the App Store* / *View*). Save → WEB_SAVE_IOS. |
| Platform: **Android Chrome** (`android`) | Save → WEB_SAVE_ANDROID (Create-contact intent) with WEB_SAVE_VCF fallback. |
| Platform: **In-app browser** (`inapp`, e.g. Telegram) | Header *"{name} · Cardy"* / *cardy.link*; warning banner *"Open in browser to save contact"* + *Open* (→ external browser; toast *Opened in Safari*). Save → toast *Open in browser to save*. |
| WEB_SHAREBACK_SHEET | **Auto-opens on page load** (when card available). *"Exchange contacts with {first}"* / *"Send yours and save {first}’s in one step."* Fields: Name (*Your name*), Phone (*+998*, tel), Telegram (*@username*); footer *"Add a phone or Telegram — at least one."*; Met at (*Where did we meet? Optional*). *"🔒 Only {first} will see this."* Missing-data hint *"Add your name to send."* / *"Add a phone or Telegram to send."*; button *"Send & Save {first}’s Contact"* (disabled until valid); *Skip*. |
| WEB_CONFIRMATION | Green check, *"Done! {first} got your contact."* / *"It arrives with where you met, so a follow-up is easy."*; *"Save {first}’s Contact"* (if not yet saved) or row *"{first}’s contact is saved"*; Get Cardy CTA card; *"Back to {first}’s Card"*; *"Changed your mind?"* + *Remove my contact* (toast *Your contact was removed*; deletes the share-back). Send also auto-triggers the native save sheet (unless already saved or in-app browser). |
| WEB_SAVE_IOS | vCard preview sheet: *Cancel*; avatar/name/company; *Create New Contact*, *Add to Existing Contact*; field list. → toast *Saved to Contacts*. |
| WEB_SAVE_ANDROID | Google Contacts "Create contact" (X, *Save*, *Saving to Google account*, *Add picture*, First name, Last name, Company, Phone (Mobile), Email; *"Filled in from {first}’s Cardy page."*). |
| WEB_SAVE_VCF | Fallback hint card *"Open the downloaded file → Contacts"* with breadcrumb *Downloads › {first-last}.vcf › Contacts*; download snackbar *"{file}.vcf · Download complete · 2 KB"* / *Open*. |
| WEB_UNAVAILABLE | When link paused or card deleted (no personal data shown): link-break icon, *"This card isn’t available right now."* / *"The link may be paused or removed. Ask the person for a new one."* / *"Made with Cardy"*. |

Also pending (plan.md): desktop layout + App Store redirect.

---

## 3. Flows

### 3.1 First launch & onboarding
1. App start → if signed in → HOME; if launched from a deferred deep link and new → DEFERRED_WELCOME (after auth/setup? see §9 Q22); else ONB_WELCOME.
2. Welcome 3 pages (Skip anytime) → AUTH_SIGNUP.

### 3.2 Authentication
- **Apple**: Sign in with Apple → backend exchange → session. Prefill name/email in setup.
- **Google**: Google Sign-In (present in v8 UI) → session.
- **Email (passwordless magic link)**: validate (empty / format) inline → request link → AUTH_CHECK_EMAIL (*"It expires in 15 minutes."*, Resend). Link opens app via Universal Link → session → SETUP_PROFILE (new) or HOME (existing).
- **Sign In** (existing account) — same providers; existing users skip setup.
- **Sign Out** → confirm → ONB_WELCOME (clear local data/keychain).

### 3.3 Setup → first card
1. SETUP_PROFILE: photo, name (required), title, company, phone, email.
2. SETUP_PERMISSIONS: per-row Allow triggers real system prompts (mic, notifications, camera, local network). States: not determined / allowed / denied (denied → "Turn On in Settings").
3. *Create My First Card* or *Skip* → HOME with CARD_CREATE presented.
4. Default privacy after setup (prototype): Phone = Connections, Email = Public, Telegram = Public, Website = Public, LinkedIn = Connections.

### 3.4 Card creation (CARD_CREATE)
- Entry checks: Free & cards ≥ 2 → ALERT_CARD_LIMIT [Not Now, See Pro].
- Paths: Template → gallery → details; AI → questions → gen → results → details; Blank → details (minimal template).
- Publish: creates Card (name, slug, design, visible fields) and publishes web page; on network failure → ALERT_PUBLISH_FAILED, card kept as **draft** and auto-published when online.
- Done → HOME (toast *Card Published*) or Share Now → SHARE_SHEET. New card becomes the active card.
- Card design defaults (`newSpec`): template minimal, palette ink, mode dark, font system, align left, density balanced, bg solid, qr on, showPhoto on, showLogo on, fields {phone, email, telegram, website: on; linkedin: off}.

### 3.5 Card editing (CARD_EDITOR)
- Five tabs (see §2.5.24). Constraints:
  - Editorial template and Ocean/Ember palettes are Pro.
  - Terminal forces Mono font; Editorial forces Serif ("This template sets its own typeface").
  - Gradient template forces gradient background.
  - Private fields can't be toggled on.
  - Density caps visible contact lines (2/3/5).
- Done → save + republish web page/Wallet pass; toast *"{Name} Card Published"*.

### 3.6 Card management
- Rename (Card Settings), set default (menu or toggle; at least one default always), reorder (Move Up/Down → Home order), duplicate (Free limit), delete (confirm; link + QR stop working; can't delete last; default reassigns), export, pause (global "Pause All Links" in Profile; "Pause This Link" in share sheet).

### 3.7 Sharing with non-app users
1. **QR_FULLSCREEN**: brightness raised to max on open (restore on close); choose card; QR encodes `https://cardy.link/c/{slug}` (EC level M, 4-module quiet zone, black on white, no logo). Paused → dimmed + "Link Paused".
2. **Offline QR** toggle: QR encodes a **vCard** (contact only; no analytics/Connect) — works without internet.
3. **SHARE_SHEET**: system share targets + Copy Link + Wallet + Save Image/PDF + Pause This Link.
4. **Export**: PNG/PDF/Wallet/Lock Screen.
5. **Widgets**: Lock/Home screen QR.
6. **Offline**: Home banner *"You're offline. Your QR code still works."* — QR must render from local data.

### 3.8 "Who did you just meet?" (JUST_MET)
- Trigger A: QR_FULLSCREEN dismissed after being shown > 2 s.
- Trigger B: SHARE_SHEET dismissed after the user performed a share action (target or action).
- Save requires a name; creates a lightweight connection (`via: qr`, `pendingMerge: true`, title "Met via your QR", event/place from active event, note), optional reminder. Skip = nothing saved.
- Later web share-back with the **same first name** (case-insensitive) and no phone/Telegram duplicate → merges into this connection (`merged: true`), shows "Merged" row and toast *Merged with your QR note*.

### 3.9 Web share-back (recipient side)
1. Recipient opens link (camera scan / tap). Server returns card or unavailable (paused/deleted → WEB_UNAVAILABLE, no personal data).
2. Page loads; share-back sheet auto-opens. Recipient may Skip.
3. Validation: name required AND (phone OR Telegram). Send disabled with hint until valid.
4. Send & Save: POST share-back (name, phone, telegram, metAt). Then auto-open native save of owner's contact (iOS vCard preview; Android create-contact intent, `.vcf` fallback; in-app browser: not possible → prompt to open in browser).
5. Confirmation; "Remove my contact" deletes the share-back (needs a removal token).
6. Copy phone/email; Message on Telegram (t.me link); Save to Contacts (vCard).
7. Track stats: page view, save, share-back (feeds "Viewed · Saved · Shared back").
- Consent: explicit action + *"Only {first} will see this."* (no checkbox in v8; see §9 Q19).

### 3.10 Owner receives share-back
1. Server creates/updates the owner's connection:
   - **Dedupe**: if an existing connection has the same phone (digits only) or same Telegram (case-insensitive) → merge silently (fill missing phone/telegram), no new row.
   - Else if a `pendingMerge` connection with the same first name exists → merge (`merged: true`).
   - Else new connection: name, phone, telegram, title "Contact", company "Shared from your web page", `via: web`, event = active event name else recipient's "Met at" text, place = active event place.
2. Push PUSH_SHAREBACK: *"{first} shared their contact with you"* / *"{event}"* or *"From your web page"*.
3. Tap push: merged → CONNECTION_DETAIL + toast *Merged with your QR note*; has note → CONNECTION_DETAIL; else PEOPLE + ADD_CONTEXT (kind web).
4. People row shows **via web** badge; tap (no note) → ADD_CONTEXT.
5. Home card stats "Shared back" increments.

### 3.11 Deferred deep link
1. Recipient taps Smart App Banner *View* or *Get Cardy* → App Store; install.
2. First launch resolves deferred link context (owner/card slug, event) → DEFERRED_WELCOME: owner already added to their People; *Connect* sends their card back (two-way connection); *Not Now* → HOME.

### 3.12 Connect (Nearby / Tap Phones)
1. Open CONNECT (People nav, QR "Connect Nearby", card menu). Select card to share (default = active/default/event card).
2. **Nearby**: advertise + browse other app users with Connect open (respecting "Show in Nearby"). List shows name + title · company.
3. Tap *Connect* on a person → request sent → *Waiting…* (only one outstanding).
   - Accepted → CONNECTED (both receive each other's chosen card).
   - Declined → notice *"{first} declined your request."*
   - No response (timeout) → notice *"{first} didn’t respond. They may have closed Connect."*
4. **Tap Phones**: hold tops of phones together; both must have Connect open; proximity triggers exchange.
5. **Incoming** live request while CONNECT open → INCOMING_REQUEST (Accept → CONNECTED; Decline → toast).
6. **Async requests** (push PUSH_CONNECT_REQUEST *"{name} wants to connect"* / *"{event} · {place}"*) → PEOPLE Requests section → Accept (adds connection directly; shares default card) / Decline (confirm; *"They won’t be notified."*).
7. **Empty**: no one nearby → hint + Show QR.
8. CONNECTED: Save (context + note + follow-up) or Not Now (connection still saved).

### 3.13 Scan
- **QR mode**: detect QR → Cardy URL → fetch public profile → SCANNED_CARD → *Connect* (request/match) or *Add to Contacts* (iOS Contacts + ADD_CONTEXT, `via` none). Non-card QR → invalid alert with *Open in Safari*. Paste Link reads clipboard URL.
- **Paper mode**: shutter → on-device OCR → PAPER_REVIEW (editable detected fields + context) → *Save Contact* → connection `via: paper` → CONNECTION_DETAIL. OCR fail → alert (Enter Manually / Retake).
- Camera denied → in-screen state with Open Settings / Paste Link.
- Flashlight toggle.

### 3.14 Context Capture block (shared component)
Used by CONNECTED, ADD_CONTEXT, PAPER_REVIEW.
1. **Where You Met** (header + "✨ Auto"): *Event* (input), *Place* (input), *Time* (read-only, e.g. *"Today, 14:32"*). Auto-fill: active event name + place; otherwise the connection's known event/place (or location — §9 Q16). Footer *"Filled in automatically. Tap a field to change it."*
2. **Private Note**: multiline *"What did you talk about?"* + mic button (first use → mic permission flow; recording state *"Listening… tap the mic to stop"*; transcript appended). Tag chips (multi-select): **Investor, Client, Hiring, Partner, Friend**. Footer *"Only you can see this."*
3. **Follow Up**: chips *Tomorrow / In 3 days / Next week / Pick a date* (single-select toggle; first selection checks Free limit). When selected: *Date* (custom only, min today, default +5 days), *Time* (default 10:00), *To do* (placeholder *Send deck*), *Via* segmented Telegram | Email | Call (default: telegram if they have it, else email, else call). Footer *"Cardy will remind you {tomorrow | on Tue, Sep 29} at 10:00. Only you see it."*
- **Commit rules**: upsert connection (move to top of list); if connection existed and its previous event differs → push previous {event, place, date} into `meetings` (Earlier Meetings); keep old note/tags unless new provided; place string "Place, City" split into place + city; set `via`; if follow-up chosen → create reminder (what default *"Follow up"*) and **replace** any other open reminder for that connection.

### 3.15 People management
- Search, filters (All / Events / Places), swipe (Note / Remove), long-press (Open / Add Note / Remove), Remove with Undo (one-sided: *"Your note will be deleted. They keep the card you shared."*), Block (*"Your cards will look like they don’t exist to them."*), edit note/context/tags, contact actions (message/call/mail/save to Contacts), view their shared card and fields (connections-only fields visible after connecting).

### 3.16 Follow-ups
- **Create**: Context capture chips, JUST_MET chips, Connection detail chips, REMINDER_EDIT (+), Event "Follow up with everyone".
- **Free limit**: max 5 open (not done) reminders → ALERT_FU_LIMIT *"Follow-up Limit Reached"* / *"The Free plan includes 5 active reminders. You have {n}. Mark one done, or upgrade for unlimited reminders."* [Not Now, Upgrade]. (Prototype doesn't check in JUST_MET and Follow-up-all — §9 Q13.)
- **Actions**: Done/Undo, Snooze (+1 swipe; menu +1/+3/+7/custom), Edit, Delete (confirm in editor; immediate in long-press menu), channel action opens Telegram/Mail/Phone.
- **Delivery**: on due date/time (default 10:00) via push (*"Follow up with {name}"* / *"{reason}"*, actions *Open Telegram* and *Snooze 1 Day*) or Telegram bot. Reminders are private ("The other person is never notified.").
- Home shows overdue + today (max 3); widget shows count + 2.

### 3.17 Events
1. Start (Home row; Free: one active) → START_EVENT: calendar suggestions, name (required), place, dates, card to share → *Event Started*.
2. While active: Home banner; Scan/Connect show event pill; every new connection from QR (just met), Nearby, Tap Phones, web share-back, paper card is tagged with the event + place.
3. EVENT_DETAIL: stats, follow-up-all, people list, briefing (Pro), export (Pro), End.
4. Edit event: rename cascades to tagged connections (*Event Updated*).
5. End (manual confirm or automatic after last day) → EVENT_ENDED summary (and Event Summary notification if enabled). Resume available on the last event.
6. People → Events filter lists all events (derived from connections' event names + active event).

### 3.18 AI
- **Card designs**: 3 questions → 3 designs (quota 3/mo Free, 30/mo Pro).
- **Person recap** and **event briefing/recap**: generated from private notes, follow-ups, meetings. Pro feature (Free has limited free recaps). "Made only from your private notes. Nothing is shared."
- **Voice notes**: speech-to-text; "Audio isn’t stored."

### 3.19 Paywall & subscription
- Triggers: card limit (create/duplicate), Pro template/palette, AI quota exhausted, second active event, follow-up limit, CSV/CRM export, Subscription page upgrade/change plan.
- Purchase via StoreKit; returns to originating route; restore purchases; renewal terms shown; cancel via App Store (alert copy exists). Downgrade: cards beyond two become read-only.

### 3.20 Settings
- Notifications (toggles + delivery channel + Telegram bot linking + OS-denied state), Privacy & Data (discovery toggles, analytics, download data, blocked list, delete account), Subscription, Help, Appearance (Dark/Light), Language (en/uz/ru), Pause All Links, Sign out, Delete account (download data first; confirm; Pro warning).

### 3.21 Offline behaviour
- Home banner; QR fullscreen must work (cached card + link; Offline QR vCard option). Card publish queued as draft. (Other offline behaviour unspecified — §9 Q36.)

### 3.22 Permissions summary
| Permission | Requested in | Denied behaviour |
|---|---|---|
| Notifications | Setup | Settings → Notifications shows "Notifications Are Off" + Open iOS Settings |
| Camera | Setup / first scan | SCAN "Camera Access Needed" state |
| Microphone (+ Speech recognition, implied) | Setup / first mic tap (mic alert) | ALERT *"Microphone Is Off"* / *"Allow microphone access in Settings › Cardy to add notes by voice."* [Cancel, Open Settings] |
| Local Network (Nearby Devices) | Setup / CONNECT | (not specified) |
| Contacts (write), Photos (add), Calendar (read), Location (implied) | Not in prototype list | §9 Q16, Q17 |

---

## 4. Data model

Types are indicative (Swift-ish). IDs are server UUIDs unless noted. Timestamps ISO-8601 UTC.

### 4.1 Enums

```swift
enum AuthProvider { apple, google, email }
enum ContactFieldKind: CaseIterable { phone, email, telegram, website, linkedin }   // fixed display order
enum FieldPrivacy { public_, connectionsOnly, private_ }                             // "Public" / "Connections" / "Private"
enum CardTemplate { minimal, professional, modern, bold, gradient, split, terminal, stack, editorial /*Pro*/ }
enum CardPalette { graphite, snow, ink, sand, ocean /*Pro*/, ember /*Pro*/ }
enum CardAppearance { light, dark }
enum CardFont { system, rounded, serif, mono }          // "Default", "Rounded", "Serif", "Mono"
enum CardAlignment { leading, center }
enum CardDensity { minimal /*2*/, balanced /*3*/, detailed /*5*/ }
enum CardBackground { solid, gradient }
enum ConnectionSource { nearby, tapPhones, scanQR, justMet /*"via qr"*/, webShareBack /*"via web"*/, paper, contactsCapture, connectRequest, deferredLink }
enum FollowUpChannel { telegram, email, call }
enum ConnectRequestStatus { pending, accepted, declined, expired /*timeout*/, cancelled }
enum ConnectMethod { nearby, tapPhones, scan, emailLookup, deferred }
enum EventStatus { active, ended }
enum Plan { free, pro }
enum ProProduct { yearly /*$19.99*/, monthly /*$2.99*/ }
enum ReminderDelivery { push, telegramBot }
enum AppAppearance { dark, light }                      // prototype default: dark
enum AppLanguage { en, uz, ru }
enum ExportFormat { png1x, png2x, png3x, pdfSingle, pdfA4, walletPass, lockScreen16Pro, lockScreenSE }
enum CRMExportTarget { csv, googleSheets, hubspot, amoCRM, bitrix24 }
```

### 4.2 Entities

**User / Account**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| authProviders | [AuthProvider] | |
| email | String | login email (Apple/Google/email) |
| createdAt | Date | |
| plan | Plan | derived from Entitlement |
| defaultCardId | Card.ID | always set when ≥1 card |
| linksPaused | Bool | "Pause All Links" |
| language, appearance | AppLanguage, AppAppearance | local + synced (optional) |

**Profile** (1:1 User) — source of all card values
| Field | Type | Notes |
|---|---|---|
| fullName | String | required |
| jobTitle | String? | |
| company | String? | |
| photo | ImageAsset? | used by Modern/Split/Stack templates; avatar everywhere |
| logo | ImageAsset? | used by Professional template |
| fields | [ContactFieldKind: ContactField] | |

**ContactField**: `value: String?`, `privacy: FieldPrivacy`. Defaults: phone=connectionsOnly, email=public, telegram=public, website=public, linkedin=connectionsOnly.

**Card**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| ownerId | User.ID | |
| name | String | e.g. "Work", "Personal", "Conference" |
| slug | String | unique; `{firstname}-{4 chars}`; URL `cardy.link/c/{slug}` |
| sortOrder | Int | Home order |
| design | CardDesign | |
| publishState | enum { draft, published } | draft when publish failed offline |
| isPaused | Bool? | if per-card pause adopted (§9 Q5) |
| readOnly | Bool | after Pro downgrade beyond 2 cards |
| createdAt/updatedAt | Date | |
| stats | CardStats | server-computed |

**CardDesign**
| Field | Type | Default |
|---|---|---|
| template | CardTemplate | minimal |
| palette | CardPalette | ink |
| appearance | CardAppearance | dark |
| font | CardFont | system (ignored by terminal=mono, editorial=serif) |
| alignment | CardAlignment | leading |
| density | CardDensity | balanced |
| background | CardBackground | solid (gradient template forces gradient) |
| showQR | Bool | true |
| showPhoto | Bool | true |
| showLogo | Bool | true |
| visibleFields | Set<ContactFieldKind> | phone, email, telegram, website |

**Palette definitions** (static; `[background, foreground, accent]`):
| Palette | Pro | Light | Dark |
|---|---|---|---|
| Graphite | | #F5F5F7, #111114, #1C1C1E | #0B0B0C, #F5F5F7, #FFFFFF |
| Snow | | #FFFFFF, #000000, #000000 | #000000, #FFFFFF, #FFFFFF |
| Ink | | #FFFFFF, #0A1F44, #1D4ED8 | #08111F, #E8EEF9, #60A5FA |
| Sand | | #F7F2EA, #2B2118, #A05A16 | #1A1410, #F5EFE6, #F59E0B |
| Ocean | ✓ | #F0F9FF, #06283D, #0369A1 | #041B2B, #E0F2FE, #38BDF8 |
| Ember | ✓ | #FFF7F5, #3A1410, #C02626 | #1B0B08, #FFEDE9, #F87171 |
Derived: muted = fg 66% mixed into bg; rule = fg at 24% alpha; panelTint = accent 24% mixed into bg; gradient fill = linear 140°, bg at 22% → (accent 40% into bg).

**CardStats** (per card, server): `views: Int` ("Viewed"), `saves: Int` ("Saved" — Save to Contacts on web), `shareBacks: Int` ("Shared back"), `scans: Int?` (planned), `newConnectionsThisWeek: Int` (widget).

**Connection / Person** (owner-private)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| ownerId | User.ID | |
| remoteUserId | User.ID? | set if the person is an app user (enables their card + connections-only fields) |
| name | String | |
| title, company | String? | share-back: "Contact" / "Shared from your web page"; just-met: "Met via your QR" |
| phone, email, telegram, website, linkedin | String? | as visible to owner |
| avatar | ImageAsset? | (prototype uses initials) |
| theirCard | CardSnapshot? | design + visible values of the card they shared (for "Shared Card") |
| mySharedCardId | Card.ID? | "You shared your Work card with {first}" |
| source | ConnectionSource | drives "via web" badge, "via qr/paper" meta |
| context | MeetingContext | current meeting |
| meetings | [MeetingContext] | earlier meetings (history) |
| eventId | Event.ID? | link to event if tagged |
| note | String | private |
| tags | [String] | from presets Investor/Client/Hiring/Partner/Friend or free text (comma separated) |
| merged | Bool | share-back merged into just-met record |
| pendingMerge | Bool | just-met record awaiting a share-back |
| createdAt, updatedAt | Date | "ago" derived |
| isBlocked | Bool | (or separate Block entity) |

**MeetingContext**: `eventName: String?`, `eventId: UUID?`, `place: String?`, `city: String?`, `metAt: Date` (shown as "Sep 24" / "Today, 14:32").

**Event**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| ownerId | User.ID | |
| name | String | required |
| place | String? | "Hyatt Regency, Tashkent" |
| startDate, endDate | Date | "Sep 24 – 26"; auto-end after endDate |
| cardId | Card.ID | "Card to Share" |
| status | EventStatus | Free: ≤1 active |
| calendarEventIdentifier | String? | if created from EventKit suggestion |
| endedAt | Date? | |
| derived stats | people, withNotes, openFollowUps | |

**FollowUp / Reminder**
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| connectionId | Connection.ID | |
| title ("what") | String | default "Follow up"; e.g. "Send the pitch deck" |
| channel | FollowUpChannel | default by available fields |
| dueAt | Date (date + time) | default time 10:00 local; min today |
| isDone | Bool | |
| completedAt | Date? | |
| createdAt | Date | |
| Free limit | ≤5 where !isDone | |

**ConnectRequest / ExchangeRequest**
| Field | Type |
|---|---|
| id | UUID |
| fromUserId, toUserId | User.ID |
| fromCardId | Card.ID (card offered) |
| toCardId | Card.ID? (card returned on accept) |
| method | ConnectMethod |
| eventContext | MeetingContext? |
| status | ConnectRequestStatus |
| createdAt, respondedAt, expiresAt | Date |

**NearbyPeer** (ephemeral, client-only): `peerToken`, `userId`, `name`, `title`, `company`, `avatar`, `cardPreview`.

**ShareBack** (web submission)
| Field | Type | Notes |
|---|---|---|
| id | UUID | |
| cardId / ownerId | | |
| name | String | required |
| phone | String? | at least one of phone/telegram |
| telegram | String? | |
| metAtText | String? | "Where did we meet? Optional" |
| eventId | Event.ID? | owner's active event at submission time |
| platform | enum { ios, android, inapp, desktop } | analytics |
| removalToken | String | for "Remove my contact" |
| resultingConnectionId | Connection.ID | |
| mergeResult | enum { created, dedupedByPhoneOrTelegram, mergedWithJustMet } | |
| createdAt, removedAt | Date | |

**Subscription / Entitlement**: `plan`, `productId`, `expiresAt`, `willRenew`, `renewsAt` (shown "Renews Sep 28, 2027"), `originalTransactionId`, `environment`.

**Quotas**: `aiDesignsRemaining` (3 Free / 30 Pro per month), `aiRecapsRemaining` (Free 3/month), `periodResetsAt`.

**NotificationPrefs**: `followUpReminders=true`, `eventSummary=true`, `delivery: ReminderDelivery = push`, `telegramLinked: Bool`, `connectRequests=true`, `cardSaved=true`, `weeklySummary=false`, `productNews=false`.

**PrivacySettings**: `findByEmail=true`, `showInNearby=true`, `shareAnalytics=true`; `blockedUserIds: [UUID]`.

**DeviceRegistration**: `apnsToken`, `deviceId`, `locale`, `timezone`.

**LocalOnly state**: permission statuses, onboarding completion, active card index, last QR-open timestamp (JUST_MET heuristic), widget snapshot (App Group: default card QR payload, name, follow-ups top 2, counts).

**AIInsight** (transient): `kind: recap|briefing`, `title`, `subtitle`, `lines: [(kind: place|history|note|promise|tip|people, text)]`, `footer`.

### 4.3 Relationships
- User 1—1 Profile; User 1—N Card (≥1); User → defaultCard.
- User 1—N Connection; Connection N—1 Event (optional); Connection 1—N MeetingContext (history); Connection 1—N FollowUp (one "open" typical).
- User 1—N Event (Free: ≤1 active); Event → Card (card to share).
- ConnectRequest links two Users; accept creates a Connection on **both** sides.
- ShareBack belongs to Card/Owner and creates/updates a Connection for the owner.
- Card 1—1 public web page + Wallet pass + stats.

---

## 5. Backend interactions (candidate API)

Everything below implies a server; the prototype simulates them. REST shown; realtime via WebSocket/SSE where noted.

### 5.1 Auth & account
| Method | Path | Purpose |
|---|---|---|
| POST | /v1/auth/apple | Exchange SIWA identityToken/authorizationCode → session (+ name/email prefill) |
| POST | /v1/auth/google | Exchange Google idToken → session |
| POST | /v1/auth/email/link | Send magic link (expires 15 min); also Resend |
| POST | /v1/auth/email/verify | Verify token from Universal Link → session |
| POST | /v1/auth/refresh · /v1/auth/logout | Session lifecycle |
| DELETE | /v1/me | Delete account (cards, links → inactive page, notes) |
| POST | /v1/me/export | "Download My Data" → emailed link |

### 5.2 Profile & settings
| Method | Path | Purpose |
|---|---|---|
| GET/PATCH | /v1/me/profile | Name, title, company, contact fields + privacy |
| PUT | /v1/me/profile/photo · /v1/me/profile/logo | Image upload (multipart / presigned URL) |
| GET/PATCH | /v1/me/settings | Notification prefs, privacy toggles (findByEmail, showInNearby, analytics), language, default card, linksPaused |
| GET/POST/DELETE | /v1/me/blocks | Blocked people |
| POST | /v1/me/devices | Register APNs token, timezone |

### 5.3 Cards & publishing
| Method | Path | Purpose |
|---|---|---|
| GET | /v1/cards | List own cards |
| POST | /v1/cards | Create + publish (assign slug) — drafts queued offline |
| PATCH | /v1/cards/{id} | Update name/design/visible fields → republish page + push Wallet pass update |
| DELETE | /v1/cards/{id} | Delete; link & QR stop working |
| POST | /v1/cards/{id}/duplicate | Duplicate (Free limit enforced server-side) |
| PUT | /v1/cards/order | Reorder |
| POST | /v1/cards/{id}/pause · /resume | Per-card pause (if adopted); global via settings |
| GET | /v1/cards/{id}/stats | Viewed / Saved / Shared back / scans |
| GET | /v1/cards/{id}/wallet-pass | Signed `.pkpass` |
| — | PassKit Web Service (`/v1/passes/...` register/unregister/serial updates/log) | Pass auto-update "updates when you edit" |
| POST | /v1/ai/card-designs | {use, style, appearance} → 3 CardDesigns (quota) |

### 5.4 Public web (unauthenticated)
| Method | Path | Purpose |
|---|---|---|
| GET | /c/{slug} | Server-rendered public page (platform-adaptive; Smart App Banner meta with app-argument) |
| GET | /api/public/cards/{slug} | JSON: owner first/last name, title, company, **Public** fields ∩ visible fields, design, status (available/paused/deleted) |
| GET | /c/{slug}.vcf | vCard download (Android fallback, iOS preview) |
| POST | /api/public/cards/{slug}/events | Analytics: view, save, copy_phone, copy_email, telegram_open, get_app |
| POST | /api/public/cards/{slug}/shareback | {name, phone?, telegram?, metAt?} → {shareBackId, removalToken}; rate-limited, validated; triggers owner push |
| DELETE | /api/public/sharebacks/{id} | "Remove my contact" (removalToken) |
| GET | /.well-known/apple-app-site-association | Universal Links (`/c/*`, auth links) |
| POST/GET | /v1/deferred-links/claim | Resolve install attribution → {ownerId, cardSlug, eventName} for DEFERRED_WELCOME |

### 5.5 Connections & scanning
| Method | Path | Purpose |
|---|---|---|
| GET | /v1/connections?since= | Sync list (delta) |
| POST | /v1/connections | Create from paper card, just-met, contacts capture, connected context |
| PATCH | /v1/connections/{id} | Note, tags, context, merge flags |
| DELETE | /v1/connections/{id} | Remove (one-sided; undo = re-create/soft-delete restore) |
| POST | /v1/connections/{id}/block | Block |
| GET | /v1/public-profiles/{slug} | Scanned Cardy QR → profile visible to me (public, or connections-only if connected) |

### 5.6 Connect / exchange
| Method | Path | Purpose |
|---|---|---|
| POST | /v1/connect/sessions | Start a Connect session; returns ephemeral discovery token (advertised over MPC/BLE/UWB) |
| GET | /v1/connect/peers?tokens= | Resolve discovered tokens → name/title/company/avatar (respect showInNearby/blocks) |
| POST | /v1/connect/requests | {toToken or toUserId, cardId, method, eventId?} |
| GET | /v1/connect/requests?status=pending | Incoming requests (People "Requests") |
| POST | /v1/connect/requests/{id}/accept | {cardId} → connections created on both sides |
| POST | /v1/connect/requests/{id}/decline | |
| WS | /v1/realtime | Live: incoming request, accepted/declined/expired (for "Waiting…" UI) |
| POST | /v1/connect/by-email | (implied by "Find Me by Email") |

### 5.7 Events
| Method | Path | Purpose |
|---|---|---|
| GET/POST | /v1/events | List / start (Free: ≤1 active) |
| PATCH | /v1/events/{id} | Edit (rename cascades) |
| POST | /v1/events/{id}/end · /resume | End / resume; server auto-ends after endDate and sends Event Summary push |
| GET | /v1/events/{id}/summary | Stats, people without notes |
| POST | /v1/events/{id}/export | {target: csv / googleSheets / hubspot / amoCRM / bitrix24} (Pro) — CRM OAuth integrations |

### 5.8 Follow-ups & notifications
| Method | Path | Purpose |
|---|---|---|
| GET/POST/PATCH/DELETE | /v1/followups | CRUD (Free limit 5 open, enforced server-side) |
| POST | /v1/followups/bulk | "Follow up with everyone I haven't yet" |
| POST | /v1/integrations/telegram/link | Get bot deep link `t.me/CardyRemindBot?start={token}`; bot webhook confirms linking |
| (server) | Scheduler | Due reminders → APNs or Telegram bot message with reply link |
| (server) | Push types | connect_request, connect_result, shareback_received, card_saved, followup_due, event_summary, weekly_summary, product_news |

### 5.9 AI
| Method | Path | Purpose |
|---|---|---|
| POST | /v1/ai/recap | {connectionId} → recap lines (quota) |
| POST | /v1/ai/briefing | {eventId} → briefing/recap lines (quota) |
| (on-device) | — | Speech-to-text (no server), OCR (no server) |

### 5.10 Subscriptions
| Method | Path | Purpose |
|---|---|---|
| POST | /v1/subscriptions/verify | StoreKit 2 signed transaction → entitlement |
| POST | /v1/webhooks/app-store | App Store Server Notifications v2 (renew, cancel, refund, expire → read-only cards) |
| GET | /v1/me/entitlements | Plan, quotas, renewal date |

### 5.11 Analytics
| Method | Path | Purpose |
|---|---|---|
| POST | /v1/analytics | Opt-in usage analytics (respect "Share Usage Analytics") |

---

## 6. iOS native capabilities

| Capability / framework | Used by (screen IDs) | Notes |
|---|---|---|
| **Sign in with Apple** (AuthenticationServices) | AUTH_SIGNUP | Name/email prefill (SETUP_PROFILE footer). Credential revocation handling. |
| **Google Sign-In SDK** | AUTH_SIGNUP | "Continue with Google". |
| **Universal Links / Associated Domains** | AUTH_CHECK_EMAIL (magic link), SCAN (cardy.link URLs), deep links from widgets/push | `applinks:cardy.link` (Metly domain TBD). |
| **Deferred deep linking** (server attribution / clipboard / App Clip) | DEFERRED_WELCOME | No IDFA; see §9 Q21. |
| **AVFoundation camera + QR detection** or **VisionKit DataScannerViewController** | SCAN | QR codes; torch via `AVCaptureDevice.torchMode`. |
| **Vision OCR** (`VNRecognizeTextRequest`) + `NSDataDetector` / DataScanner text | SCAN paper mode, PAPER_REVIEW | "Read on your iPhone" — on-device; field classification (name/title/company/phone/email/telegram). |
| **UIPasteboard** | SCAN Paste Link | Paste Cardy URL (paste permission prompt / PasteButton). |
| **MultipeerConnectivity** (+ Bonjour, Local Network permission) | CONNECT Nearby, SETUP_PERMISSIONS ("Find Devices on Your Local Network") | `NSLocalNetworkUsageDescription`, `NSBonjourServices`. |
| **NearbyInteraction** (UWB) and/or CoreMotion bump detection | CONNECT Tap Phones | "Hold the top of your iPhone near theirs" — NameDrop is not available to 3rd parties; NI distance threshold (U1/U2 devices) with MPC token exchange; fallback for non-UWB devices. Requires NI permission prompt. |
| **Contacts / ContactsUI** (`CNContactStore`, `CNContactViewController`) | CONNECTION_DETAIL "save", CONNECTED "Add to Contacts", SCANNED_CARD "Add to Contacts" | Contacts permission not in prototype list. |
| **User Notifications** (APNs remote + local) | All PUSH_*, SETTINGS_NOTIFICATIONS, SETUP_PERMISSIONS | Categories with actions: follow-up → "Open Telegram", "Snooze 1 Day". Local scheduling of reminders (10:00) as offline fallback. Time-sensitive optional. |
| **Speech** (`SFSpeechRecognizer`, on-device) + **AVAudioSession** mic | Context capture mic, JUST_MET mic | "Audio isn’t stored". Needs Speech Recognition permission in addition to Mic. |
| **PhotosUI** (`PhotosPicker`) | PROFILE avatar, SETUP_PROFILE, CARD_EDITOR Media (photo, logo) | |
| **Photos (add-only)** `PHPhotoLibrary` | CARD_EXPORT PNG "Save to Photos", Lock Screen wallpaper | `NSPhotoLibraryAddUsageDescription`. |
| **Files / ShareLink / UIActivityViewController** | SHARE_SHEET, CARD_EXPORT PDF "Save to Files", EVENT_EXPORT CSV | Custom sheet in prototype; system share for targets. |
| **ImageRenderer / PDFKit / Core Graphics** | CARD_EXPORT (PNG 1–3×, PDF 85×55 mm with 3 mm bleed + crop marks, A4 10-up), Lock Screen image | |
| **Core Image `CIQRCodeGenerator`** | QR_FULLSCREEN, CardFace, widgets, exports, Wallet | EC level M, 4-module quiet zone; offline vCard payload. |
| **PassKit** (`PKAddPassesViewController`) | CARD_EXPORT Wallet, SHARE_SHEET "Add to Apple Wallet" | Server-signed pass + web service for updates. |
| **WidgetKit** (+ App Groups, App Intents for config) | WIDGET_FOLLOWUPS_M (systemMedium), WIDGET_QR_S (systemSmall), WIDGET_CARD_M (systemMedium), WIDGET_LOCK_QR_RECT (accessoryRectangular), WIDGET_LOCK_QR_CIRC (accessoryCircular) | Widget taps deep-link to QR_FULLSCREEN / REMINDER_EDIT. Card selection via AppIntent configuration. |
| **App Intents** | Widgets config; optional Shortcuts/Siri ("Show my QR", "Start event"), Control Center control for QR | Not explicit in prototype; recommended. |
| **UIScreen brightness** | QR_FULLSCREEN ("Brightness raised") | Restore on dismiss. |
| **EventKit** (read) | START_EVENT "From Your Calendar" suggestions | Calendar permission not in prototype list. |
| **CoreLocation** (+ reverse geocoding) | Context capture "Place" auto-fill, START_EVENT Dates row map-pin | Implied; not in permission list (§9 Q16). |
| **StoreKit 2** | PAYWALL, SETTINGS_SUBSCRIPTION | Products yearly/monthly; restore; `manageSubscriptionsSheet` for cancel/change. |
| **SFSafariViewController / openURL** | PROFILE Preview Public Page, Help links, Terms/Privacy, invalid QR "Open in Safari" | |
| **URL schemes**: `tg://`/`https://t.me/`, `mailto:`, `tel:`, `sms:`, WhatsApp | Follow-up channel actions, CONNECTION_DETAIL actions, push action "Open Telegram", Telegram bot linking | `LSApplicationQueriesSchemes`. |
| **Haptics** (UIFeedbackGenerator / sensoryFeedback) | Long-press preview, swipe actions, connect success | Implied iOS pattern. |
| **Context menus with preview** | CARD_PREVIEW_MENU, MENU_PERSON_ROW, MENU_REMINDER_ROW | Native `contextMenu(menuItems:preview:)`. |
| **Swipe actions** | PEOPLE rows, FOLLOWUPS rows | Native `swipeActions`. |
| **Pull-down menus** (`Menu`) | Privacy, Appearance, Language, Snooze, Person picker, card "…" | |
| **Background tasks** (BGAppRefresh) | Widget/reminder refresh, draft publish retry | |
| **Network reachability** (`NWPathMonitor`) | HOME offline banner, publish queue | |
| **Keychain** | Session tokens | |
| **Local persistence** (SwiftData/Core Data) | Offline-first People/Follow-ups/Cards | |
| **Localization** (String Catalogs) | en, uz (Latin), ru | |
| **Dark/Light appearance override** | PROFILE Appearance | `preferredColorScheme`. |
| **Foundation Models / server LLM** | AI_INSIGHT, CARD_CREATE AI | Provider TBD (§9 Q25). |

---

## 7. Copy catalog

(Screen-specific copy is inline in §2.5. This section consolidates alerts, toasts, pushes, empty states and i18n.)

### 7.1 Alerts

| ID | Title | Message | Actions |
|---|---|---|---|
| ALERT_SIGN_OUT | Sign Out? | You can sign back in with Apple, Google or email. | Cancel · **Sign Out** (destructive) |
| ALERT_DELETE_CARD | Delete “{name}” Card? | Its link and QR code will stop working. People you’ve connected with keep your details. | Cancel · Delete (destructive) |
| ALERT_CARD_LIMIT (create) | Card Limit Reached | The Free plan includes 2 cards. Delete one, or upgrade to Cardy Pro for unlimited cards. | Not Now · See Pro |
| ALERT_CARD_LIMIT (duplicate) | Card Limit Reached | The Free plan includes 2 cards. Upgrade to Cardy Pro to duplicate this one. | Not Now · See Pro |
| ALERT_PRO_TEMPLATE | {Template} Is a Pro Template | Upgrade to Cardy Pro to use Editorial and every palette. | Not Now · See Pro |
| ALERT_PUBLISH_FAILED | Couldn’t Publish Card | Check your connection. Your card is saved as a draft and will publish when you’re back online. | OK |
| ALERT_INVALID_QR | No Business Card Found | This QR code opens {domain}. It isn’t a Cardy or vCard code. | Cancel · Open in Safari |
| ALERT_PAPER_NOT_READ | Couldn’t Read the Card | Hold the card flat in good light, or type the details yourself. | Enter Manually · Retake |
| ALERT_REMOVE | Remove {first}? | Your note will be deleted. They keep the card you shared. | Cancel · Remove (destructive) |
| ALERT_BLOCK | Block {first}? | Your cards will look like they don’t exist to them. | Cancel · Block (destructive) |
| ALERT_DECLINE_REQUEST | Decline {first}’s Request? | They won’t be notified. | Cancel · Decline (destructive) |
| ALERT_END_EVENT | End {event}? | New connections won’t be added to it. You’ll get a summary. | Cancel · End Event (destructive) |
| ALERT_ONE_EVENT | One Active Event on Free | End {event} first, or upgrade to run several events at once. | Not Now · Upgrade |
| ALERT_FU_LIMIT | Follow-up Limit Reached | The Free plan includes 5 active reminders. You have {n}. Mark one done, or upgrade for unlimited reminders. | Not Now · Upgrade |
| ALERT_DELETE_REMINDER | Delete Reminder? | You won’t be reminded to follow up with {first}. | Cancel · Delete (destructive) |
| ALERT_MIC_OFF | Microphone Is Off | Allow microphone access in Settings › Cardy to add notes by voice. | Cancel · Open Settings |
| ALERT_PERM_SETTINGS | Turn On in Settings | Open iOS Settings › Cardy to allow {permission}. | Cancel · Open Settings |
| ALERT_TELEGRAM_BOT | Connect Telegram Bot | Open @CardyRemindBot and tap Start. Reminders arrive in the chat with a link to reply. | Cancel · Open Telegram |
| ALERT_CANCEL_PRO | Cancel Cardy Pro? | You keep Pro until the end of this billing period. Cards beyond two become read-only after that. | Keep Pro · Cancel (destructive) |
| ALERT_DELETE_ACCOUNT | Delete Account? | This can’t be undone. | Cancel · Delete (destructive) |
| ALERT_PRO_INFO (unused in v8) | Cardy Pro | Unlimited cards, Editorial and every palette, and 30 AI designs a month. | Not Now · Learn More |
| SYSTEM prompts | see §2.5.5 (mic, notifications, camera, local network) | Info.plist usage strings: mic "Cardy turns your voice notes into text. Audio isn’t stored."; camera "Cardy uses the camera to scan business card QR codes."; local network "Cardy uses your local network to connect with people nearby." | Don’t Allow · Allow |

Alert button convention: first (cancel) regular weight, last bold; destructive red.

### 7.2 Toasts (HUD, 2 s; with Undo 4 s)

| Context | Text |
|---|---|
| Cards | Link Copied · Sent via {AirDrop/Messages/Telegram/WhatsApp/Mail} · Card Published · {Name} Card Published · {Name} is your default · Card Duplicated · Card Deleted · You need at least one card · Pick another card as default · Gradient template is always gradient · Change privacy in Profile first · Links Paused · Links Resumed |
| Export | Saved to Photos · Saved to Files · Added to Wallet · Wallpaper Saved · CSV Saved to Files · Opened in Google Sheets · Sent to HubSpot · Sent to amoCRM · Sent to Bitrix24 |
| People | Connected with {first} · Connection Removed (+Undo) · Blocked · Note Saved · Added to Contacts · Opening {message/call/mail} · Request Declined · Merged with your QR note · Contact Removed |
| Capture | Saved · Reminder Set · Connection Saved · Contact Saved · Context Saved · Saved {first} |
| Follow-ups | Marked Done (+Undo) · Moved Back (+Undo) · Snoozed to {date} (+Undo) · Snoozed to Tomorrow · Reminder: {date} · Reminder Set · Reminder Updated · Reminder Deleted · Choose a person first · {N} reminders set for tomorrow · Opening {Telegram/Mail/Call} |
| Events | Event Started · Event Updated · Event Resumed · Add an event name |
| Auth/Setup | Link Sent · Add your name to continue · Account Deleted |
| Scan | Torch On · Camera Allowed · Opening Safari |
| Settings | Telegram Connected · Link sent to your email · Opening {Settings/guide/Mail/Terms/Privacy Policy/App Store/Blocked People} · Welcome to Cardy Pro · No purchases to restore · Purchases Restored · Subscription Cancelled |
| Web | Phone Copied · Email Copied · Saved to Contacts · Contact Saved · Open in browser to save · Opened in Safari · Your contact was removed · Opening Telegram |

### 7.3 Push notifications

| ID | Title (app name) | Body | Subtitle/2nd line | Tap → | Actions |
|---|---|---|---|---|---|
| PUSH_CONNECT_REQUEST | Cardy | {Full name} wants to connect | {event} · {place} | PEOPLE (Requests) | — |
| PUSH_FOLLOWUP | Cardy | **Follow up with {Full name}** | {reason}, e.g. "Design review you promised at Tashkent Tech Week." | FOLLOWUPS | Open Telegram (channel) · Snooze 1 Day |
| PUSH_SHAREBACK | Cardy | {first} shared their contact with you | {event} or "From your web page" | ADD_CONTEXT / CONNECTION_DETAIL | — |
| PUSH_CARD_SAVED (implied) | Cardy | (someone added you to Contacts) | | | |
| PUSH_EVENT_SUMMARY (implied) | Cardy | (event ended: who you met, what's left) | | EVENT_ENDED | |
| PUSH_WEEKLY_SUMMARY (implied, quiet) | Cardy | (new connections and card views) | | | |
| PUSH_PRODUCT_NEWS (implied) | | | | | |

### 7.4 Empty / informational states
- HOME follow-ups: "Nothing due today. {N} coming up." / "No follow-ups yet. Add one right after you connect — it takes 2 seconds."
- HOME recent: "People you connect with show up here. Open Connect at your next event."
- HOME offline: "You're offline. Your QR code still works."
- PEOPLE: "No Connections Yet" / "Scan someone's card or open Connect. Your notes about them stay private." / [Open Connect]; "No Results for “{q}”" / "Check the spelling or try a new search."
- FOLLOWUPS: "No Follow-ups Yet" / "Add one right after you connect — it takes 2 seconds."
- CONNECT: "No One Nearby Yet" / "Ask them to open Connect in Cardy, or show your QR code instead." / [Show QR]
- SCAN denied: "Camera Access Needed" / "Allow camera access in Settings to scan cards. You can still paste a link." / [Open Settings] [Paste Link]
- WEB unavailable: "This card isn’t available right now." / "The link may be paused or removed. Ask the person for a new one."
- Notifications off: "Notifications Are Off" / "Notifications are turned off for Cardy in iOS Settings. You won’t hear about connect requests."

### 7.5 i18n — keys translated in prototype (en / uz / ru)

| Key | en | uz | ru |
|---|---|---|---|
| home | Home | Asosiy | Главная |
| scan | Scan | Skan | Скан |
| people | People | Kontaktlar | Контакты |
| profile | Profile | Profil | Профиль |
| hi | Hi | Salom | Привет |
| showQR | Show QR | QR ko‘rsatish | Показать QR |
| share | Share | Ulashish | Поделиться |
| recent | Recent | So‘nggilar | Недавние |
| seeAll | See All | Hammasi | Все |
| search | Search | Qidirish | Поиск |
| all | All | Hammasi | Все |
| events | Events | Tadbirlar | События |
| places | Places | Joylar | Места |
| requests | Requests | So‘rovlar | Запросы |
| accept | Accept | Qabul qilish | Принять |
| decline | Decline | Rad etish | Отклонить |
| contact | Contact Details | Kontakt maʼlumotlari | Контакты |
| cards | Cards | Kartalar | Карточки |
| settings | Settings | Sozlamalar | Настройки |
| signOut | Sign Out | Chiqish | Выйти |
| language | Language | Til | Язык |
| whereMet | Where You Met | Qayerda tanishdingiz | Где познакомились |
| privNote | Private Note | Shaxsiy qayd | Личная заметка |
| followUp | Follow Up | Eslatma | Напомнить |
| peopleMet | People You Met | Tanishgan odamlar | С кем познакомились |
| newFu | New Reminder | Yangi eslatma | Новое напоминание |
| newCard | New Card | Yangi karta | Новая карточка |
| fuToday | Follow Up Today | Bugun bog‘lanish kerak | Связаться сегодня |
| followUps | Follow-ups | Eslatmalar | Напоминания |
| done | Done | Bajarildi | Готово |
| snooze | Snooze | Keyinroq | Отложить |
| startEvent | Start Event | Tadbirni boshlash | Начать мероприятие |
| startEventSub | Everyone you meet is tagged automatically | Uchrashgan har bir kishi avtomatik belgilanadi | Все новые знакомые отмечаются автоматически |
| endEvent | End | Tugatish | Завершить |
| inProgress | In progress | Davom etmoqda | Идёт |
| myCards | My Cards | Kartalarim | Мои карточки |

All other strings are English-only in the prototype (full i18n is an open item in plan.md).

---

## 8. Prototype tweaks (props) and implications

| Tweak | Values (default) | What it does in the prototype | Implication for iOS |
|---|---|---|---|
| `appTheme` | `dark` \| `light` (dark) | App colour scheme; also switchable in Profile → Appearance. | Support both; Appearance setting overrides system (no "System" option in v8 — §9 Q28). Dark is the primary design. |
| `tint` | `teal` \| `nocturne` \| `blue` \| `cardy` (teal) | Accent colour. teal: fill #0F766E, dark-mode tint #2DD4BF, light tint #0F766E; nocturne: purple (#796cbf fill / #9184d9 tint dark, #6a5db3 light); blue: system blue; cardy: #3B5BFF (#6B8AFF dark tint). | Single app AccentColor = teal (decision in plan.md). Web page also uses #0F766E. |
| `tabStyle` | `island` \| `classic` (island) | Floating rounded "island" tab bar (inset 20pt, bottom 26pt, 62pt high, pill highlight on selected) vs standard edge-to-edge tab bar (83pt). | Use native `TabView`; on iOS 26 the Liquid Glass tab bar is floating natively — island style maps to that. |
| `demoData` | `full` \| `empty` (empty saved) | `empty` hides all connections, pending requests and follow-ups → exercises empty states. | Empty states are required; seed/demo data useful for previews & UI tests. |
| `offline` | bool (true saved) | Shows Home offline banner. | Reachability-driven banner; QR must work offline. |
| `start` | `app` \| `onboarding` (app) | Initial phase: in-app vs welcome. | Launch routing (signed in vs not). |
| `freePlan` | bool (true) | When true and not purchased, Free limits apply (cards 2, follow-ups 5, events 1, AI 3, Pro templates/palettes, export). False = treat as Pro. | Entitlement-driven gating; debug override for QA. |
| `screen` (hidden) | jump label | Opens a named state (see Appendix A). | Use as SwiftUI preview / UI-test fixture catalogue. |
| `bare` (hidden) | bool | Renders phone frame only. | n/a |

Other prototype constants: today = Sat Sep 26 2026; demo timings (Connect wait 1.6 s, AI generation 1.7 s, voice transcription 2.2 s, long-press 480 ms, JUST_MET threshold 2 s, toast 2 s / 4 s with Undo, swipe reveal 148pt with 60pt threshold).

---

## 9. Open questions / ambiguities

**Branding & domains**
- **Q1.** Rename all "Cardy" copy to "Metly": domain (`cardy.link/c/{slug}`), Telegram bot `@CardyRemindBot`, `support@cardy.app`, "Get Cardy", "Made with Cardy", Terminal template text `~/cardy $ whoami`, Wallet pass logo. Confirm Metly equivalents.

**Auth & profile**
- **Q2.** v8 offers **Google** sign-in in addition to Apple and email magic link — keep Google? "Sign In" (existing account) currently follows the same path as sign-up; define returning-user flow, provider linking, and email-change.
- **Q3.** Company is collected in setup but **not editable in Profile** (only name + title inline). Website and LinkedIn are not in setup. Add Company row? More field types (WhatsApp, Instagram, address, multiple phones)?
- **Q4.** Privacy semantics per surface: in-app card renders, exports (PNG/PDF/Wallet/Lock Screen) and widgets include **Connections-only** fields (e.g., phone), while the web page shows **Public** only. Printed cards would expose connections-only data. Confirm intended visibility per surface.

**Cards & links**
- **Q5.** "Pause All Links" (Profile) and "Pause This Link" (Share sheet) toggle the **same** global state in the prototype. Is per-card pause required?
- **Q6.** "Preview Public Page" renders the **default card**; each card has its own slug — should each link render its own card? (Assumed yes.)
- **Q37.** Card slug format/uniqueness and whether users can customise slugs. Editorial template shows a static "No. 01" — meaning?
- **Q12.** Editor applies changes live; **Cancel doesn't revert** and Done "publishes". Need draft/discard semantics and offline publish queue behaviour (draft cards: are they shareable via QR before publish?).

**Connect / exchange**
- **Q7.** Nearby technology choice: MultipeerConnectivity (Local Network prompt matches the prototype's permission copy) vs BLE; **Tap Phones** via NearbyInteraction (UWB-only devices) or motion "bump" — NameDrop is not available to third parties. Android peers can't Connect at all.
- **Q8.** SCANNED_CARD **Connect** jumps straight to "You're Connected" — should it send a request that the other side must accept?
- **Q9.** Inconsistency: People "Decline" says *"They won’t be notified"*, but the Connect screen shows the requester *"Kamila declined your request."*
- **Q10.** "Find Me by Email" exists in Privacy, but there is **no UI to send a connect request by email**.
- **Q11.** Accepting from People Requests adds the connection directly; accepting the live incoming overlay shows the CONNECTED context screen. Unify?
- **Q47.** During an active event, does the event's "Card to Share" override the default/active card in Connect, QR and People "Accepting shares your Work card"?

**Follow-ups**
- **Q13.** Free limit (5 active) is **not enforced** in JUST_MET chips and "Follow Up with Everyone I Haven’t Yet". Also capture flows replace any existing open reminder for that person (one open per person), while "New Reminder" allows multiples. Confirm rules.
- **Q14.** Swipe Snooze is always +1 day; Home Snooze menu offers +1/+3/+7/custom. OK?
- **Q15.** Reminder delivery: local notifications vs server push; Telegram bot requires server-side scheduling and time-zone handling; what if the user travels? Notification content privacy on lock screen?

**Events, context, permissions**
- **Q16.** Event **Dates** row has no picker in the prototype (display + map-pin icon). Auto-end needs end date/time zone. Calendar suggestions need **EventKit** permission and "Place"/auto-context implies **Location** permission — neither is in the setup permission list. Should context include GPS/reverse-geocoded place when no event is active?
- **Q17.** Voice notes need **Speech Recognition** permission in addition to Microphone; on-device only? Languages (uz/ru)?
- **Q18.** Share-back merge into a "Who did you just meet?" record uses **first-name match only** — collision risk (two "Sardor"s). Need a confirmation UI or stronger matching?
- **Q31.** People "Places" groups by **city** — source of city (event place, geocoding, typed)?
- **Q45.** Capture "Time" is read-only ("Today, 14:32") — editable?
- **Q43.** JUST_MET heuristic (QR visible >2 s; after a share action) — also after Offline QR? Rate-limit so it doesn't nag?

**Web share-back & privacy/legal**
- **Q19.** No explicit consent checkbox on the share-back form (only "Only {first} will see this"). Legal basis (GDPR / Uzbekistan personal-data law), retention, spam/abuse protection (rate limits, captcha?), phone validation (default +998 only?).
- **Q20.** v6 form had an **Email** field; v8 removed it (name + phone/Telegram only). Confirm.
- **Q21.** Deferred deep linking mechanism without IDFA (server fingerprint, clipboard token, App Clip, third-party). Would an **App Clip** replace the web page for iOS recipients?
- **Q22.** DEFERRED_WELCOME appears before/after account creation? The new user has no card yet — what card is "shared back" on Connect? Does the owner need to accept?
- **Q49.** Android save logic: when to use Create-contact intent vs `.vcf` fallback.
— Desktop web layout and App Store redirect are still open (plan.md).

**AI**
- **Q25.** AI provider (on-device Foundation Models vs server LLM), data sent off-device (private notes!), quotas: recap shows PRO badge but Free has "3 free recaps left this month"; does generating AI designs consume quota even if none are used?

**Exports & integrations**
- **Q24.** Wallet pass signing (Pass Type ID cert on server) and live updates; Lock Screen export only lists 2 device sizes — generalise to current device?
- **Q26.** CRM exports (Google Sheets, HubSpot, amoCRM, Bitrix24) require OAuth integrations — in scope for v1, or CSV only?
- **Q23.** Lock Screen widget copy says "show your QR at full brightness, without unlocking" — launching app UI requires unlock; the accessory widget itself can display the QR. Clarify (maybe a Control Center control / Live Activity).

**Monetization**
- **Q27.** In-app "Cancel Subscription" must hand off to App Store subscription management (Apple rule). Define read-only behaviour for cards beyond 2 after downgrade, free trial (none shown), localized pricing (UZS), and "Cardy Pro · Free" row should reflect plan.
- **Q38.** Card limit applies to create & duplicate; deleting last card prevented. Downgrade with >5 open reminders / >1 active event — what happens?

**General**
- **Q28.** Appearance: only Dark/Light; add "System"? Default Dark.
- **Q29.** Full i18n (uz Latin / ru) — only core strings exist.
- **Q30.** Stats definitions: "Viewed" (page views or QR scans?), "Saved" (web Save to Contacts taps?), "Shared back"; per card; time window. Prototype shows identical numbers for all cards.
- **Q32.** Tab bar hidden on pushed detail screens in the prototype vs iOS convention (keep tab bar visible).
- **Q33.** Share sheet: custom (as prototyped, with Pause toggle and Wallet/Export actions) vs system `UIActivityViewController` + custom activities.
- **Q34.** "Blocked People" management screen not designed; unblock flow.
- **Q35.** Delete account: effect on other users' copies (they keep your card/details per "They keep the card you shared").
- **Q36.** Sync/offline model: offline-first local DB with server sync? Conflict resolution? Multi-device support?
- **Q39.** "Edit Note" also edits Event/Place/Tags — rename to "Edit"?
- **Q40.** Connection detail action labels are lowercase ("message", "call", "mail", "save") — capitalise?
- **Q41.** Scanning a **vCard** QR (non-Cardy) — result flow undefined (create connection + ADD_CONTEXT?).
- **Q42.** QR brightness restore on close; keep screen awake while QR shown?
- **Q44.** Paper card: is the photo of the card stored/attached to the connection?
- **Q46.** Sign-out: wipe local data?
- **Q48.** CONNECT card chooser: default selection rule (default card vs active carousel card vs event card).
- **Q50.** Light mode + Dynamic Type pass, app icon and launch screen still pending (plan.md "Open / next").

---

## Appendix A — Prototype state catalog (76 states)

Use as a checklist for SwiftUI previews / snapshot tests. Format: `# · prototype label → screen ID (state)`.

1 Welcome → ONB_WELCOME · 2 Sign up → AUTH_SIGNUP · 3 Check email → AUTH_CHECK_EMAIL · 4 Profile setup → SETUP_PROFILE · 5 Permissions → SETUP_PERMISSIONS · 6 Home → HOME · 7 Start Event → START_EVENT (new) · 8 Follow-ups → FOLLOWUPS · 9 Follow-ups · empty → FOLLOWUPS (empty) · 10 New follow-up → REMINDER_EDIT (new) · 11 Edit follow-up → REMINDER_EDIT (edit) · 12 Follow-up limit → ALERT_FU_LIMIT · 13 Follow-up push → PUSH_FOLLOWUP · 14 Long-press card → CARD_PREVIEW_MENU · 15 QR fullscreen → QR_FULLSCREEN · 16 QR · offline → QR_FULLSCREEN (offline vCard) · 17 Share sheet → SHARE_SHEET · 18 New card flow → CARD_CREATE (method) · 19 AI design results → CARD_CREATE (results) · 20 Publish failed → ALERT_PUBLISH_FAILED · 21 Connect · nearby → CONNECT (Nearby) · 22 Connect · tap phones → CONNECT (Tap) · 23 Connect · no one nearby → CONNECT (empty) · 24 Connect · declined → CONNECT (declined notice) · 25 Connect · no response → CONNECT (timeout notice) · 26 Connect · incoming → INCOMING_REQUEST · 27 Connect request push → PUSH_CONNECT_REQUEST · 28 You're connected → CONNECTED · 29 Microphone permission → system mic prompt over CONNECTED · 30 Scan → SCAN (QR) · 31 Scan · paper card → SCAN (Paper) · 32 Paper card review → PAPER_REVIEW · 33 Paper card · not read → ALERT_PAPER_NOT_READ · 34 Camera denied → SCAN (denied) · 35 Invalid QR → ALERT_INVALID_QR · 36 Scanned card → SCANNED_CARD · 37 Scanned · add context → ADD_CONTEXT (contacts) · 38 People → PEOPLE (All) · 39 People · events → PEOPLE (Events) · 40 Event detail → EVENT_DETAIL · 41 Edit event → START_EVENT (edit) · 42 Pre-event briefing → AI_INSIGHT (briefing) · 43 Export event → EVENT_EXPORT · 44 Event ended → EVENT_ENDED · 45 Swipe actions → PEOPLE (row swiped) · 46 Loading → PEOPLE (skeleton) · 47 Connection + note → CONNECTION_DETAIL · 48 AI recap → AI_INSIGHT (recap) · 49 Editor → CARD_EDITOR · 50 Export → CARD_EXPORT (PNG) · 51 Wallet pass → CARD_EXPORT (Wallet) · 52 Widgets → WIDGETS_GALLERY · 53 Web · share-back sheet → WEB_SHAREBACK_SHEET · 54 Web · iPhone → WEB_CARD (ios) · 55 Web · iOS contact preview → WEB_SAVE_IOS · 56 Web · Android → WEB_CARD (android) · 57 Web · Android create contact → WEB_SAVE_ANDROID · 58 Web · .vcf fallback → WEB_SAVE_VCF · 59 Web · in-app browser → WEB_CARD (inapp) · 60 Web · confirmation → WEB_CONFIRMATION · 61 Web · card unavailable → WEB_UNAVAILABLE · 62 Share-back push → PUSH_SHAREBACK · 63 Share-back · via web in People → PEOPLE (via web badge) · 64 Share-back · add context → ADD_CONTEXT (web) · 65 Who did you just meet? → JUST_MET · 66 Merged contact → CONNECTION_DETAIL (merged) · 67 Deferred deep link → DEFERRED_WELCOME · 68 Paywall → PAYWALL · 69 Profile & settings → PROFILE · 70 Notification settings → SETTINGS_NOTIFICATIONS · 71 Privacy & data → SETTINGS_PRIVACY · 72 Subscription → SETTINGS_SUBSCRIPTION · 73 Help & support → SETTINGS_HELP · 74 Delete account → SETTINGS_DELETE_ACCOUNT · 75 Card settings → CARD_SETTINGS · 76 Alert → ALERT_SIGN_OUT

---

## Appendix B — CardFace template specification

Common to all templates:
- Aspect ratio **85 : 55** (85×55 mm business card); corner radius ≈ 4.2% of width; all sizes below are % of card width (cqw) so the card scales from 56pt thumbnails to full width.
- Colours from palette (bg/fg/accent + derived muted, rule, panelTint); `bgFill` is gradient when template = gradient or background = gradient.
- **Contacts list** = visible fields (card toggles) with non-empty values, in order phone, email, telegram, website, linkedin, **excluding Private** (and excluding non-Public on the web page), truncated to density limit (Minimal 2 / Balanced 3 / Detailed 5). Each row: icon (accent colour unless noted) + value, single line, ellipsized. Icons: phone, envelope, telegram, globe, linkedin. Terminal keys: `tel`, `mail`, `tg`, `web`, `in`.
- **role** = "{title} · {company}" (non-empty parts). **initials** = first letters of first two name words. **monogram** = first letter of company.
- **QR plate**: white rounded square with black modules (33-module viewbox incl. quiet zone), shown when `showQR`; position/size per template.
- Photo shown only if `showPhoto` and photo exists (else initials); logo only if `showLogo` and logo exists (else monogram).
- Alignment (leading/center) honoured by **Minimal, Bold, Gradient** only.

| # | Template | Pro | Layout | Fields shown | Photo / Logo | Font | QR |
|---|---|---|---|---|---|---|---|
| 1 | **Minimal** | | Padding 7%. Top: name (6.6%, semibold) + role (3.3%, muted), max width 62%. Bottom: contacts list (max width 58%). Space-between vertical. | name, role, contacts (icons) | — | card font | bottom-right, 24% |
| 2 | **Professional** | | Padding 6.5%. Top row: logo square (9%) or monogram tile (accent bg, bg-coloured letter) left; company UPPERCASE tracked (2.6%, muted) right. Bottom: name (6%), title (3.2%, muted), accent bar (9% × 0.6%), contacts list. | name, title, company, contacts (icons) | **Logo** (fallback monogram) | card font | bottom-right, 22% |
| 3 | **Modern** | | Left accent stripe (2.2% wide, full height). Padding 7% (left 9.5%). Header: circular avatar 14% (panelTint bg) + name (5.6%) + role (3%). Bottom: contacts. | name, role, contacts (icons) | **Photo** (fallback initials) | card font | bottom-right, 22% |
| 4 | **Bold** | | Padding 6.5%. Top: company UPPERCASE in accent (2.6%, tracked, semibold). Middle: first name (11%, bold, tight) and last name (11%, accent colour). Bottom: title (3%, muted) + first **2** contact values (no icons). | first/last name, company, title, 2 contacts | — | card font | bottom-right, 20% |
| 5 | **Gradient** | | Always gradient background. Padding 7%. Top: company in outlined pill (rule colour). Middle: name (7%) + title (3.2%, muted). Bottom: contacts (icons in fg colour, not accent). | name, title, company, contacts | — | card font | bottom-right, 23% |
| 6 | **Split** | | Left panel 36% width in accent colour: circular avatar 13% (bg-coloured circle) and QR (21%) stacked, centered. Right area padding 6.5%: name (5.6%), title (3%, muted), company (2.6%, UPPERCASE, accent); bottom contacts. | name, title, company, contacts (icons) | **Photo** (fallback initials) | card font | inside left panel, 21% |
| 7 | **Terminal** | | Padding 6%, base text 3%. Lines: `~/cardy $ whoami` (muted, `$` accent); name (5.4%) with accent blinking-style `_` cursor; `# {role}` (muted); bottom: contacts as `{key} {value}` with key in accent. | name, role, contacts (keys) | — | **Mono (forced)** | bottom-right, 22% |
| 8 | **Stack** | | Centered column, padding 6% vertical / 20% horizontal: avatar circle 13% (panelTint), name (5.6%), role (3%, muted), contacts wrapped inline centered (2.7%, icons). | name, role, contacts (icons) | **Photo** (fallback initials) | card font (AI uses Rounded) | **top-right, small 15%** |
| 9 | **Editorial** | **Pro** | Padding 6.5%. Header row: "No. 01" left, company right (2.5%, UPPERCASE tracked, muted) with rule underline. Name large italic (9%). Title in accent (3.4%). Bottom: contact values only (no icons). | name, company, title, contacts (values) | — | **Serif (forced)** | bottom-right, 20% |

Fonts: Default = SF Pro (system), Rounded = SF Pro Rounded, Serif = New York, Mono = SF Mono.

Where a card face appears: Home carousel thumbnail (96pt), Profile Cards rows (56pt), editor template grid (3-col), create gallery (2-col), editor/create previews (full width), CONNECTED (two overlapping), INCOMING_REQUEST, SCANNED_CARD, CONNECTION_DETAIL "Shared Card", CARD_PREVIEW_MENU (large), SHARE_SHEET header (62pt), WIDGET_CARD_M, onboarding illustration, DEFERRED_WELCOME, WEB_CARD, PAPER_REVIEW (OCR preview mock), exports (PNG/PDF).

---

## Appendix C — Suggested work packages (for parallel agents)

| WP | Scope | Key screen IDs | Depends on |
|---|---|---|---|
| WP0 | Core: app shell, router (phases, tabs, stacks, covers, sheets), theming/accent, toast HUD with Undo, alert & menu helpers, localization infra, reachability | all | — |
| WP1 | Domain models + persistence (SwiftData) + API client + sync/offline queue + auth session (Keychain) | — | WP0 |
| WP2 | **CardFace renderer** (9 templates, 6 palettes × 2 modes, fonts, density, alignment, gradient, photo/logo, QR generator incl. offline vCard) | Appendix B | WP0 |
| WP3 | Auth & onboarding: welcome, SIWA, Google, email magic link + Universal Links, setup profile, permissions | ONB_*, AUTH_*, SETUP_* | WP0, WP1 |
| WP4 | Cards: create wizard (incl. AI designs client), editor, card settings, card menus, delete/duplicate/default/reorder, pause | CARD_CREATE, CARD_EDITOR, CARD_SETTINGS, MENU_CARD_ACTIONS, CARD_PREVIEW_MENU | WP2, WP1 |
| WP5 | Sharing & export: Home cards section, QR fullscreen (brightness, offline QR, JUST_MET trigger), share sheet, export PNG/PDF/Lock, Wallet pass add | HOME (cards), QR_FULLSCREEN, SHARE_SHEET, CARD_EXPORT, JUST_MET | WP2 |
| WP6 | Scan: camera QR, paste link, invalid QR, camera denied, scanned card, paper OCR review | SCAN, SCANNED_CARD, PAPER_REVIEW | WP2, WP8 (capture block) |
| WP7 | Connect: MPC/NI discovery, requests (live + async), incoming overlay, CONNECTED, People Requests | CONNECT, INCOMING_REQUEST, CONNECTED | WP1, WP8 |
| WP8 | People & context: People list (search/filters/swipe/long-press/undo), connection detail, note editing, Context Capture block (incl. voice notes via Speech), ADD_CONTEXT, Contacts save, block/remove | PEOPLE, CONNECTION_DETAIL, ADD_CONTEXT | WP1 |
| WP9 | Follow-ups & notifications: reminders CRUD, limits, Home "Follow Up Today", FOLLOWUPS, REMINDER_EDIT, snooze, push registration, notification categories/actions, local scheduling, push routing | FOLLOWUPS, REMINDER_EDIT, PUSH_* | WP1 |
| WP10 | Events: start/edit (EventKit suggestions), auto-tagging, Home banner, event detail, end/summary, follow-up-all, export sheet | START_EVENT, EVENT_DETAIL, EVENT_ENDED, EVENT_EXPORT | WP8, WP9 |
| WP11 | AI insights: recap & briefing sheet, quotas | AI_INSIGHT | WP1 |
| WP12 | Monetization: StoreKit 2 paywall, entitlements, gating helpers used by all WPs, subscription page | PAYWALL, SETTINGS_SUBSCRIPTION | WP1 |
| WP13 | Profile & settings: profile editing + privacy menus, appearance, language, notifications, privacy & data, help, delete account, sign-out, deferred welcome | PROFILE, SETTINGS_*, DEFERRED_WELCOME | WP1, WP12 |
| WP14 | Widgets extension (App Group snapshot, AppIntent config, deep links) | WIDGET_*, WIDGETS_GALLERY | WP2, WP9 |
| WP15 | Backend + public web (out of iOS scope): API §5, public card page, share-back, vCard, deferred links, AASA, Wallet signing, push scheduler, Telegram bot | WEB_* | — |
