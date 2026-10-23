// Minimal, escape-by-default HTML building for the server-rendered card page.

const ESCAPES: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
  '`': '&#96;',
};

/** Escapes text for HTML element content and (double- or single-quoted) attribute values. */
export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/[&<>"'`]/g, (ch) => ESCAPES[ch] ?? ch);
}

/** Markup that is already safe (built by `html` or a trusted constant). */
export class SafeHtml {
  constructor(readonly value: string) {}
  toString() {
    return this.value;
  }
}

/** Marks a trusted constant (never user data) as markup. */
export const trusted = (markup: string) => new SafeHtml(markup);

type Interpolation = SafeHtml | string | number | boolean | null | undefined | Interpolation[];

function render(value: Interpolation): string {
  if (value === null || value === undefined || value === false || value === true) return '';
  if (value instanceof SafeHtml) return value.value;
  if (Array.isArray(value)) return value.map(render).join('');
  return escapeHtml(value);
}

/** Tagged template: every interpolation is escaped unless it is `SafeHtml` (nested `html` results). */
export function html(strings: TemplateStringsArray, ...values: Interpolation[]): SafeHtml {
  let out = strings[0] ?? '';
  values.forEach((value, i) => {
    out += render(value) + (strings[i + 1] ?? '');
  });
  return new SafeHtml(out);
}

const DEFAULT_SCHEMES = ['https:', 'http:', 'tel:', 'mailto:'];

/**
 * A URL that is safe to put in `href`/`src`: absolute, without control characters, and with an
 * allowed scheme (never `javascript:`, `data:`, `vbscript:`…). Returns null otherwise.
 */
export function safeUrl(value: string | null | undefined, schemes: string[] = DEFAULT_SCHEMES): string | null {
  if (!value) return null;
  const text = value.trim();
  if (text.length === 0 || text.length > 2048 || /[\u0000-\u001F\u007F\s]/.test(text)) return null;
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  if (!schemes.includes(url.protocol)) return null;
  if ((url.protocol === 'https:' || url.protocol === 'http:') && !url.hostname) return null;
  return url.href;
}

/** `https://…` (or `http://…`) only — for images and external pages. */
export const safeHttpUrl = (value: string | null | undefined) => safeUrl(value, ['https:', 'http:']);
