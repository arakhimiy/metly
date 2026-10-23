import { deviceFamilyFromUserAgent, iosMajorFromUserAgent } from './visitor';

// Fingerprint matching for deferred links. A wrong match shows a stranger's card on someone's first
// launch, so the rules are conservative: any hard mismatch disqualifies, and only a unique, confident
// best candidate is returned.

export interface ClickCandidate {
  id: string;
  cardId: string;
  userAgent: string;
  locale: string | null;
  timeZone: string | null;
  createdAt: Date;
}

export interface Fingerprint {
  model: string;
  osVersion: string;
  locale: string;
  timeZone: string;
  preferredLanguages: string[];
}

/** Minimum score for a match: time zone plus OS version or exact locale, at least. */
export const MIN_SCORE = 5;

const normLocale = (value: string) => value.trim().replace(/_/g, '-').toLowerCase();
const language = (value: string) => normLocale(value).split('-')[0] ?? '';

/** Score of a click whose IP prefix already matched; null = disqualified. */
export function scoreClick(click: ClickCandidate, fp: Fingerprint): number | null {
  let score = 0;

  // Time zone: the strongest signal after the network. Clicks without one (no JavaScript) only
  // match by explicit token.
  if (!click.timeZone || click.timeZone !== fp.timeZone) return null;
  score += 3;

  // OS major version from the browser user agent vs the app's osVersion.
  const uaMajor = iosMajorFromUserAgent(click.userAgent);
  const fpMajor = Number.parseInt(fp.osVersion, 10);
  if (uaMajor !== null && Number.isFinite(fpMajor)) {
    if (uaMajor !== fpMajor) return null;
    score += 2;
  }

  // Device family: an iPhone click never matches an iPad install and vice versa. Android/Windows clicks
  // cannot become an iOS install on the same device.
  const family = deviceFamilyFromUserAgent(click.userAgent);
  const model = fp.model.toLowerCase();
  const fpFamily = model.startsWith('iphone') ? 'iphone' : model.startsWith('ipad') ? 'ipad' : 'other';
  if (family === 'other') return null;
  if (family === 'iphone' || family === 'ipad') {
    if (fpFamily !== 'other' && family !== fpFamily) return null;
    if (family === fpFamily) score += 1;
  }

  // Locale: browser language vs the device's preferred languages / region locale.
  if (click.locale) {
    const clickLocale = normLocale(click.locale);
    const deviceLocales = [...fp.preferredLanguages, fp.locale].map(normLocale);
    if (deviceLocales.includes(clickLocale)) score += 2;
    else if (deviceLocales.map(language).includes(language(clickLocale))) score += 1;
  }
  return score;
}

/**
 * The best click if it is confident (≥ MIN_SCORE) and unambiguous. Ties are tolerated only between
 * clicks for the same card (one visitor tapping twice): the latest wins.
 */
export function pickClick<T extends ClickCandidate>(candidates: T[], fp: Fingerprint): T | null {
  const scored = candidates
    .map((click) => ({ click, score: scoreClick(click, fp) }))
    .filter((s): s is { click: T; score: number } => s.score !== null && s.score >= MIN_SCORE)
    .sort((a, b) => b.score - a.score || b.click.createdAt.getTime() - a.click.createdAt.getTime());
  const best = scored[0];
  if (!best) return null;
  const tied = scored.filter((s) => s.score === best.score);
  if (tied.some((s) => s.click.cardId !== best.click.cardId)) return null;
  return best.click;
}
