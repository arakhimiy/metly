import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { Prisma } from '../generated/prisma/client';
import { instagramUsername, telegramUsername } from '../web/contact-links';
import { storedPhoneLabel, storedPhones } from './phones';
import {
  type CardDesign,
  CONTACT_VALUE_MAX,
  type ContactEntry,
  ContactField,
  type ContactFieldKind,
  contactFieldKinds,
  type ContactKind,
  ContactKind as ContactKindSchema,
  FieldPrivacy,
  type LabeledPhone,
  MAX_ADDITIONAL_PHONES,
  MAX_CONTACTS,
  type PhoneLabel,
  uuid,
} from './wire';

// Contact list (docs/api/CONTACTS.md). The list is the source of truth; the legacy fields
// (`contactFields` / `phoneLabel` / `additionalPhones`, connection `phone` … `linkedin`) are derived
// from it on every write and every response, and rebuilt into it when an older app pushes without it.

type Privacy = z.infer<typeof FieldPrivacy>;
export type Audience = 'public' | 'connections';

/**
 * Ids of the entries rebuilt from a legacy primary field, so a card's `visibleContacts` keeps pointing
 * at them (phone = `LabeledPhone.primaryID` in the app).
 */
export const PRIMARY_CONTACT_IDS: Record<ContactFieldKind, string> = {
  phone: '00000000-0000-0000-0000-00000000f001',
  email: '00000000-0000-0000-0000-00000000f002',
  telegram: '00000000-0000-0000-0000-00000000f003',
  website: '00000000-0000-0000-0000-00000000f004',
  linkedin: '00000000-0000-0000-0000-00000000f005',
};

/** Privacy of a new entry (and of an empty legacy contact field). */
export const DEFAULT_CONTACT_PRIVACY: Record<ContactKind, Privacy> = {
  phone: 'connections',
  whatsapp: 'connections',
  linkedin: 'connections',
  email: 'public',
  telegram: 'public',
  instagram: 'public',
  website: 'public',
  address: 'public',
};

const legacyKinds = new Set<ContactKind>(contactFieldKinds);
export const isLegacyKind = (kind: ContactKind): kind is ContactFieldKind => legacyKinds.has(kind);

// ───────────────────────────── Stored values ─────────────────────────────

const StoredEntry = z.object({
  id: uuid,
  kind: ContactKindSchema,
  label: z.unknown().optional(),
  value: z.string(),
  privacy: FieldPrivacy.catch('connections'),
});

/**
 * `contacts` as stored (jsonb) → valid entries only, never throws: unknown kinds, empty values and
 * repeated ids are dropped, over-long values cut, phone labels defaulted, at most 10.
 */
export function storedContacts(value: unknown): ContactEntry[] {
  if (!Array.isArray(value)) return [];
  const out: ContactEntry[] = [];
  const ids = new Set<string>();
  for (const item of value) {
    if (out.length >= MAX_CONTACTS) break;
    const parsed = StoredEntry.safeParse(item);
    if (!parsed.success) continue;
    const e = parsed.data;
    const text = e.value.trim().slice(0, CONTACT_VALUE_MAX[e.kind]);
    if (!text || ids.has(e.id)) continue;
    ids.add(e.id);
    out.push({ id: e.id, kind: e.kind, label: e.kind === 'phone' ? storedPhoneLabel(e.label) : null, value: text, privacy: e.privacy });
  }
  return out;
}

// ───────────────────────────── List → legacy ─────────────────────────────

export interface LegacyContacts {
  /** One per legacy kind, in kind order: the first entry of the kind, else an empty value. */
  contactFields: ContactField[];
  /** Label of the first phone, else `mobile`. */
  phoneLabel: PhoneLabel;
  /** The phones after the first, up to 5. */
  additionalPhones: LabeledPhone[];
}

export function contactsToLegacy(list: ContactEntry[]): LegacyContacts {
  const contactFields = contactFieldKinds.map((kind): ContactField => {
    const first = list.find((e) => e.kind === kind);
    return first ? { kind, value: first.value, privacy: first.privacy } : { kind, value: '', privacy: DEFAULT_CONTACT_PRIVACY[kind] };
  });
  const phones = list.filter((e) => e.kind === 'phone');
  return {
    contactFields,
    phoneLabel: phones[0]?.label ?? 'mobile',
    additionalPhones: phones
      .slice(1, 1 + MAX_ADDITIONAL_PHONES)
      .map((p) => ({ id: p.id, label: p.label ?? 'mobile', value: p.value, privacy: p.privacy })),
  };
}

const json = (value: unknown) => value as Prisma.InputJsonValue;

/** Profile columns for a write: the list plus the legacy columns derived from it. */
export function profileContactData(list: ContactEntry[]) {
  const legacy = contactsToLegacy(list);
  return {
    contacts: json(list),
    contactFields: json(legacy.contactFields),
    phoneLabel: legacy.phoneLabel,
    additionalPhones: json(legacy.additionalPhones),
  };
}

/** Connection columns for a write: the list plus `phone` … `linkedin` derived from it. */
export function connectionContactData(list: ContactEntry[]) {
  const legacy = contactsToLegacy(list);
  const value = (kind: ContactFieldKind) => legacy.contactFields.find((f) => f.kind === kind)?.value ?? '';
  return {
    contacts: json(list),
    phone: value('phone'),
    phoneLabel: legacy.phoneLabel,
    additionalPhones: json(legacy.additionalPhones),
    email: value('email'),
    telegram: value('telegram'),
    website: value('website'),
    linkedin: value('linkedin'),
  };
}

// ───────────────────────────── Legacy → list ─────────────────────────────

export interface LegacyValue {
  value: string;
  privacy: Privacy;
}

/** What an older app (or a row from before the list) expresses. */
export interface LegacyInput {
  /** The primary value of each legacy kind (phone = the primary phone). */
  primary: Partial<Record<ContactFieldKind, LegacyValue>>;
  phoneLabel: PhoneLabel;
  additionalPhones: LabeledPhone[];
}

/**
 * Rebuilds the list from legacy fields (CONTACTS.md § Legacy → list):
 * 1. from `stored`, drop what the legacy fields express — every phone, the first email/telegram/website/linkedin;
 * 2. rebuild those from `input`: primary phone, extra phones, email, telegram, website, linkedin (non-empty);
 * 3. append the kept entries (WhatsApp, Instagram, second emails…) in stored order; cap at 10.
 *
 * A rebuilt primary entry takes the id of the stored entry it replaces (so ids stay stable when an
 * entry was created with a random id), else the fixed id of its kind; extra phones keep their ids.
 */
export function legacyToContacts(input: LegacyInput, stored: ContactEntry[] = []): ContactEntry[] {
  const replaced = new Map<ContactFieldKind, ContactEntry>();
  const kept: ContactEntry[] = [];
  for (const entry of stored) {
    if (entry.kind === 'phone') {
      if (!replaced.has('phone')) replaced.set('phone', entry);
    } else if (isLegacyKind(entry.kind) && !replaced.has(entry.kind)) {
      replaced.set(entry.kind, entry);
    } else {
      kept.push(entry);
    }
  }

  const reserved = new Set(input.additionalPhones.map((p) => p.id));
  const used = new Set<string>();
  const out: ContactEntry[] = [];
  const add = (entry: Omit<ContactEntry, 'id'>, ids: (string | undefined)[], avoid = reserved) => {
    if (out.length >= MAX_CONTACTS) return;
    const value = entry.value.trim().slice(0, CONTACT_VALUE_MAX[entry.kind]);
    if (!value) return;
    const id = ids.find((candidate) => candidate && !used.has(candidate) && !avoid.has(candidate)) ?? randomUUID();
    used.add(id);
    out.push({ ...entry, id, value });
  };
  const primary = (kind: ContactFieldKind, label: PhoneLabel | null = null) => {
    const legacy = input.primary[kind];
    if (legacy) add({ kind, label, value: legacy.value, privacy: legacy.privacy }, [replaced.get(kind)?.id, PRIMARY_CONTACT_IDS[kind]]);
  };

  primary('phone', input.phoneLabel);
  for (const phone of input.additionalPhones) {
    add({ kind: 'phone', label: phone.label, value: phone.value, privacy: phone.privacy }, [phone.id], new Set());
  }
  primary('email');
  primary('telegram');
  primary('website');
  primary('linkedin');
  for (const entry of kept) add(entry, [entry.id], new Set());
  return out;
}

/** The first non-empty value of each kind in a stored `contactFields` (parsed defensively). */
function legacyFields(value: unknown): Partial<Record<ContactFieldKind, LegacyValue>> {
  const primary: Partial<Record<ContactFieldKind, LegacyValue>> = {};
  for (const item of Array.isArray(value) ? value : []) {
    const parsed = ContactField.safeParse(item);
    if (parsed.success && parsed.data.value.trim() && !primary[parsed.data.kind]) {
      primary[parsed.data.kind] = { value: parsed.data.value, privacy: parsed.data.privacy };
    }
  }
  return primary;
}

export interface ProfileContactColumns {
  contacts?: unknown;
  contactFields: unknown;
  phoneLabel?: unknown;
  additionalPhones?: unknown;
}

/** A profile's legacy columns as legacy input. */
export function profileLegacyInput(row: ProfileContactColumns): LegacyInput {
  return { primary: legacyFields(row.contactFields), phoneLabel: storedPhoneLabel(row.phoneLabel), additionalPhones: storedPhones(row.additionalPhones) };
}

/** A profile's list; a row stored before the list (empty `contacts`) reads as the list built from its legacy columns. */
export function profileContacts(row: ProfileContactColumns): ContactEntry[] {
  const list = storedContacts(row.contacts);
  return list.length > 0 ? list : legacyToContacts(profileLegacyInput(row));
}

export interface ConnectionContactColumns {
  contacts?: unknown;
  phone: string;
  phoneLabel?: unknown;
  additionalPhones?: unknown;
  email: string;
  telegram: string;
  website: string;
  linkedin: string;
}

/** A connection's legacy columns as legacy input (privacy means nothing there: `connections`). */
export function connectionLegacyInput(row: Omit<ConnectionContactColumns, 'contacts'>): LegacyInput {
  const primary: Partial<Record<ContactFieldKind, LegacyValue>> = {};
  for (const kind of contactFieldKinds) if (row[kind].trim()) primary[kind] = { value: row[kind], privacy: 'connections' };
  return { primary, phoneLabel: storedPhoneLabel(row.phoneLabel), additionalPhones: storedPhones(row.additionalPhones) };
}

/** A connection's list; a row stored before the list reads as the list built from its legacy columns. */
export function connectionContacts(row: ConnectionContactColumns): ContactEntry[] {
  const list = storedContacts(row.contacts);
  return list.length > 0 ? list : legacyToContacts(connectionLegacyInput(row));
}

// ───────────────────────────── Cards ─────────────────────────────

/**
 * The entries a viewer may see on a card, in profile order:
 * - selection: `visibleContacts` (unknown ids ignored); a legacy card (no selection) shows every entry
 *   whose kind is in `visibleFields` — never WhatsApp/Instagram;
 * - audience: Public; Connections too for an accepted, mutual connect; Private never.
 */
export function cardContacts(list: ContactEntry[], design: Pick<CardDesign, 'visibleFields' | 'visibleContacts'>, audience: Audience): ContactEntry[] {
  let selected: ContactEntry[];
  if (Array.isArray(design.visibleContacts)) {
    const ids = new Set(design.visibleContacts.map((id) => id.toLowerCase()));
    selected = list.filter((e) => ids.has(e.id));
  } else {
    const kinds = new Set<ContactKind>(design.visibleFields ?? []);
    selected = list.filter((e) => isLegacyKind(e.kind) && kinds.has(e.kind));
  }
  return selected.filter(
    (e) => e.value.trim().length > 0 && (e.privacy === 'public' || (audience === 'connections' && e.privacy === 'connections')),
  );
}

export interface CardContactsView extends Omit<LegacyContacts, 'contactFields'> {
  /** The visible entries, profile order. */
  contacts: ContactEntry[];
  /** Legacy `fields`: the first visible entry of each legacy kind, in kind order. */
  fields: ContactField[];
}

/**
 * What a card shows of a profile, with the legacy fields older apps read derived from the visible
 * entries. `phoneLabel` falls back to the profile's first phone (sent even when the phone is hidden).
 */
export function cardContactsView(profile: ProfileContactColumns, design: CardDesign, audience: Audience): CardContactsView {
  const all = profileContacts(profile);
  const contacts = cardContacts(all, design, audience);
  const legacy = contactsToLegacy(contacts);
  const visibleKinds = new Set(contacts.map((e) => e.kind));
  return {
    contacts,
    fields: legacy.contactFields.filter((f) => visibleKinds.has(f.kind)),
    phoneLabel: contacts.find((e) => e.kind === 'phone')?.label ?? all.find((e) => e.kind === 'phone')?.label ?? 'mobile',
    additionalPhones: legacy.additionalPhones,
  };
}

// ───────────────────────────── Merging ─────────────────────────────

/** Strips scheme, leading www. and trailing slashes, lower-cased. */
function urlKey(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
    .replace(/^www\./, '')
    .replace(/\/+$/, '');
}

/** Digits only: "+998 90 555-12-34" and "998905551234" are the same number. */
export function contactDigits(value: string): string {
  return value.replace(/\P{N}/gu, '');
}

/**
 * Identity of an entry for de-duplication: kind + normalised value (digits for phone/WhatsApp, the
 * lower-cased handle for Telegram/Instagram, lower-cased address/URL otherwise). '' = cannot compare.
 */
export function contactKey(entry: Pick<ContactEntry, 'kind' | 'value'>): string {
  const value = entry.value.trim();
  let key: string;
  switch (entry.kind) {
    case 'phone':
    case 'whatsapp':
      key = contactDigits(value);
      break;
    case 'telegram':
      key = (telegramUsername(value) ?? value.replace(/^@/, '')).toLowerCase();
      break;
    case 'instagram':
      key = (instagramUsername(value) ?? value.replace(/^@/, '')).toLowerCase();
      break;
    case 'email':
      key = value.toLowerCase();
      break;
    case 'website':
    case 'linkedin':
      key = urlKey(value);
      break;
    case 'address':
      key = value.toLowerCase().replace(/[\s,.]+/g, ' ').trim();
      break;
  }
  return key ? `${entry.kind}:${key}` : '';
}

export interface MergeResult {
  contacts: ContactEntry[];
  /** The entries appended (as stored). */
  added: ContactEntry[];
  changed: boolean;
}

/**
 * Adds someone's entries to a list without duplicates (generalises `mergePhones`): an incoming entry
 * whose kind + normalised value is already there is skipped; new ones are appended, Connections-level,
 * while the list has room (10). With `adoptLabel`, a phone already there takes the label of the same
 * incoming number (its owner knows best).
 */
export function mergeContacts(target: ContactEntry[], incoming: ContactEntry[], opts: { adoptLabel?: boolean } = {}): MergeResult {
  const contacts = target.map((e) => ({ ...e }));
  const added: ContactEntry[] = [];
  let changed = false;
  const byKey = new Map<string, ContactEntry>();
  for (const e of contacts) {
    const key = contactKey(e);
    if (key && !byKey.has(key)) byKey.set(key, e);
  }
  const ids = new Set(contacts.map((e) => e.id));
  for (const candidate of incoming) {
    const value = candidate.value.trim().slice(0, CONTACT_VALUE_MAX[candidate.kind]);
    const key = contactKey({ kind: candidate.kind, value });
    if (!key) continue;
    const existing = byKey.get(key);
    if (existing) {
      if (opts.adoptLabel && existing.kind === 'phone' && candidate.label && existing.label !== candidate.label) {
        existing.label = candidate.label;
        changed = true;
      }
      continue;
    }
    if (contacts.length >= MAX_CONTACTS) continue;
    const id = ids.has(candidate.id) ? randomUUID() : candidate.id;
    const entry: ContactEntry = {
      id,
      kind: candidate.kind,
      label: candidate.kind === 'phone' ? (candidate.label ?? 'mobile') : null,
      value,
      privacy: 'connections',
    };
    ids.add(id);
    byKey.set(key, entry);
    contacts.push(entry);
    added.push(entry);
    changed = true;
  }
  return { contacts, added, changed };
}

/** A new entry with a fresh id and the kind's default label. */
export function newContact(kind: ContactKind, value: string, privacy: Privacy = DEFAULT_CONTACT_PRIVACY[kind]): ContactEntry {
  return { id: randomUUID(), kind, label: kind === 'phone' ? 'mobile' : null, value: value.trim(), privacy };
}
