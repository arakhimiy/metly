// Languages of server-made texts (push notifications, card web pages). API error
// messages are developer-facing and stay English: the app shows its own texts.

export type Lang = 'uz' | 'ru' | 'en';

export const LANGS: readonly Lang[] = ['uz', 'ru', 'en'];

/** Uzbek: the launch market. Used when nothing at all is known about the person. */
export const DEFAULT_LANG: Lang = 'uz';

/**
 * Nameshake language for a device locale (`devices.locale`: `uz_UZ`, `ru_RU`, `en_US`, `uz-Cyrl_UZ`,
 * `en`…): `uz*` → uz (Latin; there is no Cyrillic catalog), `ru*` → ru, every other language → en.
 *
 * Why English and not Uzbek for other languages: iOS always sends a locale, so `de_DE` or `tr_TR` is
 * a real person who does not read Uzbek or Russian — English serves them best. Only a missing locale
 * (no device, empty value) falls back to Uzbek, the launch market.
 */
export function langFromLocale(locale: string | null | undefined): Lang {
  const language = (locale ?? '').trim().toLowerCase().split(/[-_@.]/)[0] ?? '';
  if (!language) return DEFAULT_LANG;
  if (language === 'uz') return 'uz';
  if (language === 'ru') return 'ru';
  return 'en';
}

/**
 * Web pages: `?lang=` wins, then the browser's Accept-Language, then Uzbek. One implementation for
 * every tanishly.app page — the legal pages own it; card pages reuse it from here.
 */
export { pickLang } from '../web/legal/legal-page';

export interface PluralForms {
  /** 1, 21, 31… in Russian; exactly 1 in English. */
  one: string;
  /** Russian 2–4, 22–24… (not 12–14). Falls back to `other`. */
  few?: string;
  /** Russian 0, 5–20, 25–30…, 11–14. Falls back to `other`. */
  many?: string;
  other: string;
}

/**
 * The form of a counted noun for `n`. Russian uses one/few/many; English one/other. Uzbek nouns stay
 * singular after a number ("3 ta tanish"), so its `one` and `other` are normally the same word.
 */
export function plural(lang: Lang, n: number, forms: PluralForms): string {
  if (lang === 'ru') {
    if (!Number.isInteger(n)) return forms.other;
    const mod10 = Math.abs(n) % 10;
    const mod100 = Math.abs(n) % 100;
    if (mod10 === 1 && mod100 !== 11) return forms.one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return forms.few ?? forms.other;
    return forms.many ?? forms.other;
  }
  return n === 1 ? forms.one : forms.other;
}
