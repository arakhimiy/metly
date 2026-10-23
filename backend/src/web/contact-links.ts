import type { ContactField, ContactFieldKind } from '../records/wire';
import { safeUrl } from './html';

// Contact values as typed in the app ("@handle", "in/handle", "site.com") → tap actions and display
// text. Mirrors MetlyCardKit `ContactValueFormat`.

export interface ContactAction {
  kind: ContactFieldKind;
  /** Lowercase label shown next to the value. */
  label: string;
  /** Short key for the Terminal template. */
  key: string;
  display: string;
  /** Safe href (tel:, mailto:, https:) or null when the value cannot be linked. */
  href: string | null;
}

const LABELS: Record<ContactFieldKind, { label: string; key: string }> = {
  phone: { label: 'phone', key: 'tel' },
  email: { label: 'email', key: 'mail' },
  telegram: { label: 'telegram', key: 'tg' },
  website: { label: 'website', key: 'web' },
  linkedin: { label: 'linkedin', key: 'in' },
};

/** Bare username from "@user", "user", "t.me/user", "https://t.me/user?start=x". */
export function telegramUsername(value: string): string | null {
  let text = value.trim();
  text = text.replace(/^(https?:\/\/|tg:\/\/resolve\?domain=)/i, '');
  text = text.replace(/^(www\.)?(t\.me|telegram\.me|telegram\.dog)\//i, '');
  if (text.startsWith('@')) text = text.slice(1);
  text = text.split(/[/?#&]/)[0] ?? '';
  return /^[A-Za-z0-9_]{1,64}$/.test(text) ? text : null;
}

/** Adds `https://` when the value has no scheme; only http(s) survive. */
export function websiteUrl(value: string): string | null {
  const text = value.trim();
  if (!text || /\s/.test(text)) return null;
  const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(text) ? text : `https://${text}`;
  return safeUrl(withScheme, ['https:', 'http:']);
}

/** "site.com/path" — scheme, leading "www." and trailing slashes removed. */
export function websiteDisplay(value: string): string {
  return value
    .trim()
    .replace(/^[a-z][a-z0-9+.-]*:\/\//i, '')
    .replace(/^www\./i, '')
    .replace(/\/+$/, '');
}

export function linkedInUrl(value: string): string | null {
  const text = value.trim();
  if (!text || /\s/.test(text)) return null;
  const lower = text.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return safeUrl(text, ['https:', 'http:']);
  if (lower.includes('linkedin.com')) return safeUrl(`https://${text}`, ['https:']);
  const path = text.replace(/^\/+/, '');
  const prefixed = /^(in|company|pub)\//i.test(path) ? path : `in/${path}`;
  return safeUrl(`https://www.linkedin.com/${prefixed}`, ['https:']);
}

function linkedInDisplay(href: string): string {
  const url = new URL(href);
  const path = url.pathname.replace(/^\/+|\/+$/g, '');
  if (/^(in|company)\//i.test(path)) return path;
  return websiteDisplay(href);
}

/** The action for one contact field, or null when its value is empty. */
export function contactAction(field: ContactField): ContactAction | null {
  const value = field.value.trim();
  if (!value) return null;
  const { label, key } = LABELS[field.kind];
  switch (field.kind) {
    case 'phone': {
      const dial = value.replace(/[^\d+]/g, '').replace(/(?!^)\+/g, '');
      return { kind: field.kind, label, key, display: value, href: /\d{3,}/.test(dial) ? `tel:${dial}` : null };
    }
    case 'email': {
      const ok = /^[^\s@<>"'(),;:\\]+@[^\s@<>"'(),;:\\]+\.[^\s@<>"'(),;:\\]+$/.test(value);
      return { kind: field.kind, label, key, display: value, href: ok ? safeUrl(`mailto:${value}`, ['mailto:']) : null };
    }
    case 'telegram': {
      const username = telegramUsername(value);
      return {
        kind: field.kind,
        label,
        key,
        display: username ? `@${username}` : value,
        href: username ? `https://t.me/${username}` : null,
      };
    }
    case 'website': {
      const href = websiteUrl(value);
      return { kind: field.kind, label, key, display: websiteDisplay(value), href };
    }
    case 'linkedin': {
      const href = linkedInUrl(value);
      return { kind: field.kind, label, key, display: href ? linkedInDisplay(href) : value, href };
    }
  }
}
