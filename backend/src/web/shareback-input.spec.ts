import { describe, expect, it } from 'vitest';
import { cleanText, defaultRegion, digitsOnly, normalizePhone, normalizeTelegram, telegramKey } from './shareback-input';

describe('normalizePhone', () => {
  it('normalises local and international numbers to E.164', () => {
    expect(normalizePhone('90 123 45 67', 'UZ')).toBe('+998901234567');
    expect(normalizePhone('+998 (90) 123-45-67', 'UZ')).toBe('+998901234567');
    expect(normalizePhone('+1 415 555 2671', 'UZ')).toBe('+14155552671');
    expect(normalizePhone('(415) 555-2671', 'US')).toBe('+14155552671');
  });

  it('rejects invalid input', () => {
    expect(normalizePhone('12', 'UZ')).toBeNull();
    expect(normalizePhone('call me', 'UZ')).toBeNull();
    expect(normalizePhone('', 'UZ')).toBeNull();
    expect(normalizePhone('+998 90 123 45 67 89 00', 'UZ')).toBeNull();
  });
});

describe('defaultRegion', () => {
  it("uses the owner's phone country, else UZ", () => {
    expect(defaultRegion([{ kind: 'phone', value: '+1 415 555 2671', privacy: 'private' }])).toBe('US');
    expect(defaultRegion([{ kind: 'phone', value: '+998901234567', privacy: 'public' }])).toBe('UZ');
    expect(defaultRegion([])).toBe('UZ');
    expect(defaultRegion(null)).toBe('UZ');
  });
});

describe('normalizeTelegram', () => {
  it('accepts handles and links, returns @handle', () => {
    expect(normalizeTelegram('sardor_r')).toBe('@sardor_r');
    expect(normalizeTelegram('@Sardor_R')).toBe('@Sardor_R');
    expect(normalizeTelegram('https://t.me/sardor_r')).toBe('@sardor_r');
  });

  it('enforces 5–32 chars of [A-Za-z0-9_]', () => {
    expect(normalizeTelegram('@abcd')).toBeNull();
    expect(normalizeTelegram(`@${'a'.repeat(33)}`)).toBeNull();
    expect(normalizeTelegram('@sar-dor')).toBeNull();
    expect(normalizeTelegram('@sardor r')).toBeNull();
  });
});

describe('helpers', () => {
  it('digitsOnly / telegramKey / cleanText', () => {
    expect(digitsOnly('+998 (90) 123')).toBe('99890123');
    expect(telegramKey(' @Sardor ')).toBe('sardor');
    expect(cleanText('  Sardor\n\t Rashidov‮ ')).toBe('Sardor Rashidov');
  });
});
