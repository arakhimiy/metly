import { FieldPrivacy, LabeledPhone, type PhoneLabel, phoneLabels } from './wire';

// Labelled phones (docs/api/README.md § Labelled phones): the legacy columns `phone_label` and
// `additional_phones`, now derived from the contact list (src/records/contacts.ts).

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

/** vCard 3.0 TEL type per label. */
export const VCARD_TEL_TYPE: Record<PhoneLabel, string> = { mobile: 'CELL', work: 'WORK', home: 'HOME', other: 'VOICE' };
