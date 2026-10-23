import { describe, expect, it } from 'vitest';
import { buildVCard, escapeVCardText, foldLine, vcardFilename } from './vcard';

describe('escapeVCardText', () => {
  it('escapes backslash, semicolon, comma and newlines', () => {
    expect(escapeVCardText('a\\b;c,d\ne\r\nf\rg')).toBe('a\\\\b\\;c\\,d\\ne\\nf\\ng');
  });
});

describe('foldLine', () => {
  it('keeps short lines', () => {
    expect(foldLine('FN:Kamola')).toBe('FN:Kamola');
  });

  it('folds at 75 octets with a leading space on continuation lines', () => {
    const line = `NOTE:${'x'.repeat(200)}`;
    const physical = foldLine(line).split('\r\n');
    expect(physical.length).toBeGreaterThan(2);
    for (const p of physical) expect(Buffer.byteLength(p)).toBeLessThanOrEqual(75);
    for (const p of physical.slice(1)) expect(p.startsWith(' ')).toBe(true);
    expect(physical.map((p, i) => (i === 0 ? p : p.slice(1))).join('')).toBe(line);
  });

  it('never splits a multi-byte character', () => {
    const line = `FN:${'Камола '.repeat(20)}`;
    const physical = foldLine(line).split('\r\n');
    for (const p of physical) {
      expect(Buffer.byteLength(p)).toBeLessThanOrEqual(75);
      expect(Buffer.from(p, 'utf8').toString('utf8')).toBe(p);
    }
    expect(physical.map((p, i) => (i === 0 ? p : p.slice(1))).join('')).toBe(line);
  });
});

describe('buildVCard', () => {
  it('writes a vCard 3.0 with escaped text and URL values', () => {
    const card = buildVCard({
      fullName: 'Kamola  Yusupova',
      jobTitle: 'PM; Growth',
      company: 'Metly, Inc.',
      fields: [
        { kind: 'phone', value: '+998 90 123 45 67', privacy: 'public' },
        { kind: 'email', value: 'kamola@metly.uz', privacy: 'public' },
        { kind: 'telegram', value: '@kamola_y', privacy: 'public' },
        { kind: 'website', value: 'metly.link', privacy: 'public' },
        { kind: 'linkedin', value: 'in/kamola', privacy: 'public' },
      ],
      url: 'https://metly.link/c/kamola-ab12',
      photoUrl: 'https://cdn.metly.link/p.jpg',
    });
    expect(card.startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n')).toBe(true);
    expect(card.endsWith('END:VCARD\r\n')).toBe(true);
    expect(card).toContain('N:Yusupova;Kamola;;;\r\n');
    expect(card).toContain('FN:Kamola Yusupova\r\n');
    expect(card).toContain('ORG:Metly\\, Inc.\r\n');
    expect(card).toContain('TITLE:PM\\; Growth\r\n');
    expect(card).toContain('TEL;TYPE=CELL:+998 90 123 45 67\r\n');
    expect(card).toContain('EMAIL;TYPE=INTERNET:kamola@metly.uz\r\n');
    expect(card).toContain('URL:https://metly.link/\r\n');
    expect(card).toContain('item1.URL:https://t.me/kamola_y\r\n');
    expect(card).toContain('item1.X-ABLabel:Telegram\r\n');
    expect(card).toContain('item2.URL:https://www.linkedin.com/in/kamola\r\n');
    expect(card).toContain('item3.URL:https://metly.link/c/kamola-ab12\r\n');
    expect(card).toContain('PHOTO;VALUE=URI:https://cdn.metly.link/p.jpg\r\n');
    expect(card).not.toMatch(/[^\r]\n/);
  });

  it('omits empty organisation/title and unsafe photo URLs', () => {
    const card = buildVCard({ fullName: 'Solo', jobTitle: '', company: ' ', fields: [], photoUrl: 'javascript:alert(1)' });
    expect(card).not.toContain('ORG:');
    expect(card).not.toContain('TITLE:');
    expect(card).not.toContain('PHOTO');
    expect(card).toContain('N:;Solo;;;');
  });

  it('cannot be broken out of with newlines in values', () => {
    const card = buildVCard({ fullName: 'A\r\nEND:VCARD\r\nBEGIN:VCARD', jobTitle: '', company: '', fields: [] });
    expect(card.match(/^END:VCARD$/gm)?.length).toBe(1);
  });
});

describe('vcardFilename', () => {
  it('is ASCII and falls back to the slug', () => {
    expect(vcardFilename('Kamola Yusupova', 'kamola-ab12')).toBe('kamola-yusupova.vcf');
    expect(vcardFilename('Zoë "Q" Ångström', 'x')).toBe('zoe-q-angstrom.vcf');
    expect(vcardFilename('Камола', 'kamola-ab12')).toBe('kamola-ab12.vcf');
  });
});
