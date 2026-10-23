import { describe, expect, it } from 'vitest';
import { CONNECTIONS_CSV_HEADER, connectionsCsv, csvCell, zip } from './export-archive';

describe('csvCell', () => {
  it('quotes separators, quotes and newlines', () => {
    expect(csvCell('plain')).toBe('plain');
    expect(csvCell('a,b')).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell('line\nbreak')).toBe('"line\nbreak"');
    expect(csvCell(null)).toBe('');
  });

  it('neutralises spreadsheet formulas but keeps phone numbers', () => {
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`);
    expect(csvCell('@sardor')).toBe("'@sardor");
    expect(csvCell('+998 90 123-45-67')).toBe('+998 90 123-45-67');
    expect(csvCell('+cmd')).toBe("'+cmd");
  });
});

describe('connectionsCsv', () => {
  it('writes the header and one row per connection', () => {
    const csv = connectionsCsv([
      {
        fullName: 'Sardor',
        jobTitle: 'CTO',
        company: 'Acme',
        phone: '+998907654321',
        email: 's@acme.uz',
        telegram: '@sardor',
        website: '',
        linkedin: '',
        context: { metAt: '2026-09-26T10:00:00.000Z', eventName: 'ICT Week', place: 'Expo', city: 'Tashkent' },
        tags: ['investor', 'ai'],
        note: 'Met at the booth, "great" chat',
      },
    ]);
    const lines = csv.replace(/^﻿/, '').trimEnd().split('\r\n');
    expect(lines[0]).toBe(CONNECTIONS_CSV_HEADER.join(','));
    expect(lines[1]).toBe(
      `Sardor,CTO,Acme,+998907654321,s@acme.uz,'@sardor,,,2026-09-26T10:00:00.000Z,ICT Week,Expo,Tashkent,investor; ai,"Met at the booth, ""great"" chat"`,
    );
  });
});

describe('zip', () => {
  it('produces a ZIP archive', async () => {
    const buffer = await zip([{ name: 'a.txt', body: 'hello' }]);
    expect(buffer.subarray(0, 4).toString('latin1')).toBe('PK\u0003\u0004');
  });
});
