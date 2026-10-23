import { randomInt } from 'node:crypto';

const ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';

// Uzbek and Russian Cyrillic → Latin, so "Камола" gets kamola-xxxx rather than card-xxxx.
const CYRILLIC: Record<string, string> = {
  а: 'a', б: 'b', в: 'v', г: 'g', ғ: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z', и: 'i', й: 'y', к: 'k',
  қ: 'q', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ў: 'o', ф: 'f', х: 'x',
  ҳ: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sh', ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya',
};

/** `{firstname}` part of a slug: first word, ASCII-folded, lowercase, [a-z0-9], ≤ 20 chars, else "card". */
export function slugStem(fullName: string): string {
  const first = fullName.trim().split(/\s+/)[0] ?? '';
  const latin = [...first.toLowerCase()].map((ch) => CYRILLIC[ch] ?? ch).join('');
  const folded = latin
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]/g, '');
  return folded.length > 0 ? folded.slice(0, 20) : 'card';
}

export function slugCandidate(stem: string): string {
  let suffix = '';
  for (let i = 0; i < 4; i++) suffix += ALPHABET[randomInt(ALPHABET.length)];
  return `${stem}-${suffix}`;
}

export const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/;
