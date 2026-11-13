import { VCARD_TEL_TYPE } from '../records/phones';
import type { ContactEntry } from '../records/wire';
import { safeHttpUrl } from './html';
import { contactAction } from './contact-links';

// vCard 3.0 (RFC 2426) for "Save to Contacts": TEXT escaping, CRLF, folding at 75 octets.

const CRLF = '\r\n';
const MAX_OCTETS = 75;

/** Escapes a TEXT value: backslash, semicolon, comma and line breaks. */
export function escapeVCardText(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n|\r|\n/g, '\\n');
}

/** URI values are not TEXT-escaped; line breaks and control characters are dropped. */
function uri(value: string): string {
  return value.replace(/[\u0000-\u001F\u007F]/g, '');
}

/**
 * Folds one content line to ≤ 75 octets per physical line (continuation lines start with a space,
 * which counts toward the 75). Never splits a UTF-8 sequence.
 */
export function foldLine(line: string): string {
  if (Buffer.byteLength(line, 'utf8') <= MAX_OCTETS) return line;
  let out = '';
  let octets = 0;
  for (const ch of line) {
    const size = Buffer.byteLength(ch, 'utf8');
    if (octets + size > MAX_OCTETS) {
      out += `${CRLF} `;
      octets = 1;
    }
    out += ch;
    octets += size;
  }
  return out;
}

export interface VCardInput {
  fullName: string;
  jobTitle: string;
  company: string;
  /** The card's visible entries (already filtered by selection and audience), owner's order. */
  contacts: ContactEntry[];
  /** The card page (labelled "Nameshake"). */
  url?: string | null;
  photoUrl?: string | null;
}

export function buildVCard(input: VCardInput): string {
  const lines = ['BEGIN:VCARD', 'VERSION:3.0'];
  let item = 0;
  const labelled = (url: string, label: string) => {
    item += 1;
    lines.push(`item${item}.URL:${uri(url)}`);
    lines.push(`item${item}.X-ABLabel:${escapeVCardText(label)}`);
  };

  const name = input.fullName.trim().replace(/\s+/g, ' ');
  const words = name.split(' ').filter(Boolean);
  const given = words[0] ?? '';
  const family = words.slice(1).join(' ');
  lines.push(`N:${escapeVCardText(family)};${escapeVCardText(given)};;;`);
  lines.push(`FN:${escapeVCardText(name)}`);
  const company = input.company.trim();
  if (company) lines.push(`ORG:${escapeVCardText(company)}`);
  const title = input.jobTitle.trim();
  if (title) lines.push(`TITLE:${escapeVCardText(title)}`);

  // Phones first, in the owner's order (each label decides its TEL type), then everything else.
  for (const entry of input.contacts) {
    const value = entry.value.trim();
    if (entry.kind === 'phone' && value) lines.push(`TEL;TYPE=${VCARD_TEL_TYPE[entry.label ?? 'mobile']}:${escapeVCardText(value)}`);
  }
  for (const entry of input.contacts) {
    const action = contactAction(entry);
    if (!action) continue;
    switch (entry.kind) {
      case 'phone':
        break;
      case 'email':
        lines.push(`EMAIL;TYPE=INTERNET:${escapeVCardText(entry.value.trim())}`);
        break;
      case 'website':
        if (action.href) lines.push(`URL:${uri(action.href)}`);
        break;
      case 'whatsapp':
        if (action.href) {
          lines.push(`X-SOCIALPROFILE;TYPE=whatsapp:${uri(action.href)}`);
          labelled(action.href, 'WhatsApp');
        }
        break;
      case 'telegram':
        if (action.href) {
          lines.push(`X-SOCIALPROFILE;TYPE=telegram:${uri(action.href)}`);
          labelled(action.href, 'Telegram');
        }
        break;
      case 'instagram':
        if (action.href) {
          lines.push(`X-SOCIALPROFILE;TYPE=instagram:${uri(action.href)}`);
          labelled(action.href, 'Instagram');
        }
        break;
      case 'linkedin':
        if (action.href) labelled(action.href, 'LinkedIn');
        break;
      case 'address':
        // Street component only: a typed address isn't split into city / postcode reliably.
        lines.push(`ADR;TYPE=WORK:;;${escapeVCardText(action.display)};;;;`);
        break;
    }
  }
  if (input.url) labelled(input.url, 'Nameshake');
  const photo = safeHttpUrl(input.photoUrl);
  if (photo) lines.push(`PHOTO;VALUE=URI:${uri(photo)}`);
  lines.push('END:VCARD');
  return lines.map(foldLine).join(CRLF) + CRLF;
}

/** `kamola-yusupova.vcf` — ASCII only, safe in Content-Disposition; falls back to the slug. */
export function vcardFilename(fullName: string, fallback: string): string {
  const base = fullName
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
  return `${base || fallback}.vcf`;
}
