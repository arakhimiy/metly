import { randomUUID } from 'node:crypto';
import {
  type CardDesign,
  type ContactField,
  FieldPrivacy,
  LabeledPhone,
  MAX_ADDITIONAL_PHONES,
  MAX_PHONE_LENGTH,
  PhoneLabel,
  phoneLabels,
} from './wire';

// Labelled phones (docs/api/README.md § Labelled phones). Mirrors MetlyNetworking `PhoneMerge`.

type Audience = 'public' | 'connections';

/** The phone label as stored (text column); anything unexpected reads as `mobile`. */
export function storedPhoneLabel(value: unknown): PhoneLabel {
  return (phoneLabels as readonly string[]).includes(value as string) ? (value as PhoneLabel) : 'mobile';
}

const StoredPhone = LabeledPhone.extend({ privacy: FieldPrivacy.catch('connections') });

/** `additional_phones` as stored (jsonb) → valid entries only, never throws. */
export function storedPhones(value: unknown): LabeledPhone[] {
  if (!Array.isArray(value)) return [];
  const phones: LabeledPhone[] = [];
  for (const item of value) {
    const parsed = StoredPhone.safeParse(item);
    if (parsed.success) phones.push(parsed.data);
  }
  return phones;
}

/**
 * Extra phones a viewer may see on a card, like contact fields: only when the card shows phones,
 * non-empty, Public (or Connections for an accepted, mutual connect); Private never.
 */
export function visiblePhones(profile: { additionalPhones: unknown }, design: CardDesign, audience: Audience): LabeledPhone[] {
  if (!design.visibleFields.includes('phone')) return [];
  return storedPhones(profile.additionalPhones).filter(
    (p) => p.value.trim().length > 0 && (p.privacy === 'public' || (audience === 'connections' && p.privacy === 'connections')),
  );
}

/** vCard 3.0 TEL type per label. */
export const VCARD_TEL_TYPE: Record<PhoneLabel, string> = { mobile: 'CELL', work: 'WORK', home: 'HOME', other: 'VOICE' };

/** Digits only: "+998 90 555-12-34" and "998905551234" are the same number. */
export function phoneDigits(value: string): string {
  return value.replace(/\P{N}/gu, '');
}

export interface PhoneSet {
  phone: string;
  phoneLabel: PhoneLabel;
  additionalPhones: LabeledPhone[];
}

/**
 * Fills gaps in `target` with someone's numbers, never overwriting one already there:
 * - without a number in `phone`, their first number (primary, else the first extra) becomes it, label included;
 * - with `adoptLabel`, one of their numbers equal to `phone` lends it its label (its owner knows best);
 * - every other number not present yet is appended as Connections-level, up to 5.
 */
export function mergePhones(
  target: PhoneSet,
  incoming: { phone: string; phoneLabel: PhoneLabel; additionalPhones: LabeledPhone[] },
  opts: { adoptLabel: boolean } = { adoptLabel: true },
): PhoneSet & { changed: boolean } {
  const candidates = [{ id: null as string | null, label: incoming.phoneLabel, value: incoming.phone }, ...incoming.additionalPhones]
    .map((p) => ({ id: p.id, label: p.label, value: p.value.trim().slice(0, MAX_PHONE_LENGTH) }))
    .filter((p) => phoneDigits(p.value).length > 0);
  const out: PhoneSet = { phone: target.phone, phoneLabel: target.phoneLabel, additionalPhones: [...target.additionalPhones] };
  let changed = false;
  if (candidates.length === 0) return { ...out, changed };
  if (phoneDigits(out.phone).length === 0) {
    const first = candidates.shift()!;
    out.phone = first.value;
    out.phoneLabel = first.label;
    changed = true;
  }
  const primary = phoneDigits(out.phone);
  const same = opts.adoptLabel ? candidates.find((p) => phoneDigits(p.value) === primary) : undefined;
  if (same && same.label !== out.phoneLabel) {
    out.phoneLabel = same.label;
    changed = true;
  }
  const known = new Set([primary, ...out.additionalPhones.map((p) => phoneDigits(p.value))]);
  for (const candidate of candidates) {
    if (out.additionalPhones.length >= MAX_ADDITIONAL_PHONES) break;
    const key = phoneDigits(candidate.value);
    if (known.has(key)) continue;
    known.add(key);
    const id = candidate.id && !out.additionalPhones.some((p) => p.id === candidate.id) ? candidate.id : randomUUID();
    out.additionalPhones.push({ id, label: candidate.label, value: candidate.value, privacy: 'connections' });
    changed = true;
  }
  return { ...out, changed };
}

/** The primary phone of a contact-field list (first non-empty `phone`), or ''. */
export function primaryPhone(fields: ContactField[]): string {
  return fields.find((f) => f.kind === 'phone' && f.value.trim().length > 0)?.value ?? '';
}
