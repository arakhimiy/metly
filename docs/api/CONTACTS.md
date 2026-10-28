# Contact list (app schema 3.0.0, API `contacts`)

Replaces the fixed "one value per kind + extra phones" model with an ordered list the user builds
with **+ Add Contact**: any kind, several of the same kind, at most 10 entries. Older apps (TestFlight
1.0 (1)–(3)) keep working through the legacy fields, which the server derives from the list.

## Entry

```json
{ "id": "uuid", "kind": "whatsapp", "label": null, "value": "+998 90 123 45 67", "privacy": "connections" }
```

| Field | Rules |
|---|---|
| `id` | UUID, unique within the list, stable (cards reference it) |
| `kind` | `phone` · `whatsapp` · `telegram` · `instagram` · `email` · `website` · `linkedin` · `address` |
| `label` | `mobile` · `work` · `home` · `other` for `phone`; `null` for every other kind (ignored if sent) |
| `value` | trimmed, non-empty; ≤ 40 chars for `phone`/`whatsapp`, ≤ 200 otherwise (`website`/`linkedin` ≤ 500, `address` ≤ 300) |
| `privacy` | `public` · `connections` · `private` (on a connection it means nothing; default `connections`) |

- At most **10** entries (`MAX_CONTACTS`). Empty entries are never sent or stored.
- Order is the user's order; it is kept as sent.
- Default privacy of a new entry: `phone`, `whatsapp`, `linkedin` → `connections`; `email`, `telegram`,
  `instagram`, `website`, `address` → `public`.

Display / links:

| kind | link | vCard 3.0 |
|---|---|---|
| phone | `tel:` | `TEL;TYPE=CELL/WORK/HOME/VOICE` (from label) |
| whatsapp | `https://wa.me/<digits>` | `X-SOCIALPROFILE;TYPE=whatsapp:https://wa.me/<digits>` |
| telegram | `https://t.me/<user>` (existing rules) | `X-SOCIALPROFILE;TYPE=telegram:…` (existing) |
| instagram | `https://instagram.com/<user>` — accepts `@user`, `user`, or an instagram.com URL | `X-SOCIALPROFILE;TYPE=instagram:…` |
| email | `mailto:` | `EMAIL;TYPE=INTERNET` |
| website / linkedin | as today | `URL` / a labelled `itemN.URL` + `X-ABLabel:LinkedIn` (as today) |
| address | `https://maps.apple.com/?q=<address>` | `ADR;TYPE=WORK:;;<address>;;;;` (street component only) |

## Where it appears

- **Profile** (`ProfileIn` / profile record): `contacts: Entry[]`.
- **Connection** (`ConnectionIn` / connection record): `contacts: Entry[]`.
- **Card design**: `visibleContacts: uuid[] | null` — ids of the owner's profile entries this card shows,
  any order (rendering follows the profile order); unknown ids are ignored. `null`/absent = legacy card:
  it shows every entry whose kind is in `visibleFields` (all phones when `phone` is in it), never
  `whatsapp`/`instagram`. New apps always send it and keep `visibleFields` = the legacy kinds among the
  selected entries, so old apps render the card sensibly.
- **Public card JSON** (`/api/public/cards/{slug}`), **public profiles**, card page, vCard, Wallet pass:
  the visible entries (card selection, then audience: Public; Connections too after a mutual connect;
  Private never) as `contacts`, next to the legacy `fields` / `phoneLabel` / `additionalPhones`.
- **Card face**: the first 5 visible entries (density may show fewer); the web page shows all visible.

## Legacy fields (derived, both directions)

The server stores `contacts` (jsonb, default `[]`) on `profiles` and `connections`; the legacy columns
are kept and always rewritten from the list, so every response carries both.

**List → legacy** (every write, every response):

- `contactFields`: for each of `phone, email, telegram, website, linkedin` the **first** entry of that
  kind → `{kind, value, privacy}`; none → `{kind, value: "", privacy: default}`.
- `phoneLabel`: label of the first `phone` entry, else `mobile`.
- `additionalPhones`: the `phone` entries after the first, up to 5, as `{id, label, value, privacy}`.
- Connection columns `phone, email, telegram, website, linkedin`: value of the first entry of the kind.

**Legacy → list** (a push without `contacts`, i.e. an older app):

1. Start from the stored list and drop the entries the legacy fields can express: every `phone`
   entry and the first entry of `email`, `telegram`, `website`, `linkedin`.
2. Rebuild them from the payload: the primary phone (label `phoneLabel`), then `additionalPhones`,
   then email, telegram, website, linkedin — non-empty values only.
3. Append the kept entries (`whatsapp`, `instagram`, second emails…) in their stored order; cap at 10.

An entry rebuilt from a legacy primary field gets the fixed id of its kind, so ids stay stable and a
card's `visibleContacts` keeps pointing at it:

| kind | id |
|---|---|
| phone | `00000000-0000-0000-0000-00000000f001` (same as `LabeledPhone.primaryID`) |
| email | `00000000-0000-0000-0000-00000000f002` |
| telegram | `00000000-0000-0000-0000-00000000f003` |
| website | `00000000-0000-0000-0000-00000000f004` |
| linkedin | `00000000-0000-0000-0000-00000000f005` |

Extra phones keep their own ids. When the stored list already has an entry in that slot (the first
phone, the first email…), the rebuilt entry keeps **that entry's id** instead — it may have been
created by a new app with a random id — and takes the fixed id only when there is none (so a row from
before the list always gets the fixed ids). Ids never repeat within a list. A row stored before this change (empty `contacts`) is read as the
list built from its legacy columns with these rules — the app's 2.0.0 → 3.0.0 migration does the same.

## Merging someone's numbers into a connection

`mergePhones` generalises to entries: an incoming entry whose normalised value (digits for
`phone`/`whatsapp`, lower-cased handle/URL otherwise) is already in the list **as the same kind** is
skipped (a WhatsApp number equal to a phone number is its own entry); new ones are appended (privacy
`connections`) while the list has room. On connect accept a phone already there takes the label of the
same incoming number, as before.
