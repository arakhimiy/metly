import { type CountryCode, parsePhoneNumberFromString } from 'libphonenumber-js';
import type { ContactField } from '../records/wire';

// Share-back field normalisation (openapi `postShareBack`).

const DEFAULT_REGION: CountryCode = 'UZ';

/** Region of the owner's phone (any privacy level — it is never shown), else UZ. */
export function defaultRegion(contactFields: ContactField[] | null | undefined): CountryCode {
  const phone = (contactFields ?? []).find((f) => f.kind === 'phone' && f.value.trim())?.value;
  if (!phone) return DEFAULT_REGION;
  return parsePhoneNumberFromString(phone, DEFAULT_REGION)?.country ?? DEFAULT_REGION;
}

/** E.164 (`+998901234567`), or null when the number is not valid for any region. */
export function normalizePhone(raw: string, region: CountryCode): string | null {
  const text = raw.trim();
  if (!text || text.length > 40 || /[a-z]/i.test(text.replace(/\s*(ext\.?|x)\s*\d+$/i, ''))) return null;
  const parsed = parsePhoneNumberFromString(text, region);
  return parsed?.isValid() ? parsed.number : null;
}

/** `@handle` (5–32 chars of [A-Za-z0-9_]); accepts "handle", "@handle" and t.me links. */
export function normalizeTelegram(raw: string): string | null {
  let text = raw.trim();
  text = text.replace(/^https?:\/\//i, '').replace(/^(www\.)?(t\.me|telegram\.me)\//i, '');
  if (text.startsWith('@')) text = text.slice(1);
  return /^[A-Za-z0-9_]{5,32}$/.test(text) ? `@${text}` : null;
}

export const digitsOnly = (value: string) => value.replace(/\D/g, '');

/** Telegram handle as compared for de-duplication: no "@", lowercase. */
export const telegramKey = (value: string) => value.trim().replace(/^@/, '').toLowerCase();

/** Single-line display text: control characters removed, whitespace collapsed. */
export function cleanText(value: string): string {
  return value
    .replace(/[\u0000-\u001F\u007F​-‏‪-‮⁦-⁩]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
