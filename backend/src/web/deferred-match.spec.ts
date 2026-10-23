import { describe, expect, it } from 'vitest';
import { type ClickCandidate, type Fingerprint, pickClick, scoreClick } from './deferred-match';

const IPHONE_18 = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Version/18.1 Mobile/15E148 Safari/604.1';
const fp: Fingerprint = { model: 'iPhone17,1', osVersion: '18.1', locale: 'en_UZ', timeZone: 'Asia/Tashkent', preferredLanguages: ['en-US', 'ru-UZ'] };

const click = (overrides: Partial<ClickCandidate> = {}): ClickCandidate => ({
  id: 'c1',
  cardId: 'card-1',
  userAgent: IPHONE_18,
  locale: 'en-US',
  timeZone: 'Asia/Tashkent',
  createdAt: new Date('2026-10-23T10:00:00Z'),
  ...overrides,
});

describe('scoreClick', () => {
  it('scores time zone, OS major, device family and locale', () => {
    expect(scoreClick(click(), fp)).toBe(3 + 2 + 1 + 2);
    expect(scoreClick(click({ locale: 'en-GB' }), fp)).toBe(3 + 2 + 1 + 1);
  });

  it('disqualifies hard mismatches', () => {
    expect(scoreClick(click({ timeZone: 'Europe/Moscow' }), fp)).toBeNull();
    expect(scoreClick(click({ timeZone: null }), fp)).toBeNull();
    expect(scoreClick(click({ userAgent: IPHONE_18.replace('18_1', '17_5') }), fp)).toBeNull();
    expect(scoreClick(click({ userAgent: 'Mozilla/5.0 (Linux; Android 14)' }), fp)).toBeNull();
    expect(scoreClick(click({ userAgent: 'Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X)' }), fp)).toBeNull();
  });
});

describe('pickClick', () => {
  it('returns the unique confident best', () => {
    const best = click({ id: 'best' });
    const weaker = click({ id: 'weak', cardId: 'card-2', locale: 'de-DE' });
    expect(pickClick([weaker, best], fp)?.id).toBe('best');
  });

  it('returns null when two cards tie', () => {
    expect(pickClick([click({ id: 'a' }), click({ id: 'b', cardId: 'card-2' })], fp)).toBeNull();
  });

  it('tolerates ties on the same card and takes the latest', () => {
    const early = click({ id: 'early', createdAt: new Date('2026-10-23T10:00:00Z') });
    const late = click({ id: 'late', createdAt: new Date('2026-10-23T10:05:00Z') });
    expect(pickClick([early, late], fp)?.id).toBe('late');
  });

  it('returns null below the minimum score', () => {
    // Desktop-mode iPad: no OS or family signal; locale mismatch → only the time zone.
    const weak = click({ userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', locale: 'de-DE' });
    expect(pickClick([weak], fp)).toBeNull();
    expect(pickClick([], fp)).toBeNull();
  });
});
