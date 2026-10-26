import type { ContactField } from '../records/wire';
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
  /** Already filtered to Public ∩ visibleFields. */
  fields: ContactField[];
  /** The card page (labelled "Tanishly"). */
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

  for (const field of input.fields) {
    const action = contactAction(field);
    if (!action) continue;
    switch (field.kind) {
      case 'phone':
        lines.push(`TEL;TYPE=CELL:${escapeVCardText(field.value.trim())}`);
        break;
      case 'email':
        lines.push(`EMAIL;TYPE=INTERNET:${escapeVCardText(field.value.trim())}`);
        break;
      case 'website':
        if (action.href) lines.push(`URL:${uri(action.href)}`);
        break;
      case 'telegram':
        if (action.href) {
          lines.push(`X-SOCIALPROFILE;TYPE=telegram:${uri(action.href)}`);
          labelled(action.href, 'Telegram');
        }
        break;
      case 'linkedin':
        if (action.href) labelled(action.href, 'LinkedIn');
        break;
    }
  }
  if (input.url) labelled(input.url, 'Tanishly');
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
