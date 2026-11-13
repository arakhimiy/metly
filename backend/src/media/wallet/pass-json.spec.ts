import { describe, expect, it } from 'vitest';
import { buildPassJson, paletteColors, rgb } from './pass-json';

const design = {
  template: 'minimal',
  palette: 'ink',
  appearance: 'dark',
  font: 'system',
  alignment: 'leading',
  density: 'balanced',
  background: 'solid',
  showQR: true,
  showPhoto: false,
  showLogo: false,
  visibleFields: ['phone', 'email', 'telegram', 'website'],
};

const input = (overrides: { deletedAt?: Date | null; slug?: string | null; jobTitle?: string; company?: string } = {}) => ({
  card: {
    id: '7b0c2f3e-1d2a-4c5b-9e8f-0a1b2c3d4e5f',
    name: 'Work',
    slug: overrides.slug === undefined ? 'kamola-ab12' : overrides.slug,
    design,
    passAuthToken: 'token-token-token-token-1234',
    deletedAt: overrides.deletedAt ?? null,
  },
  profile: {
    fullName: 'Kamola Yusupova',
    jobTitle: overrides.jobTitle ?? 'Product Manager',
    company: overrides.company ?? 'Nameshake',
    contactFields: [
      { kind: 'phone', value: '+998901234567', privacy: 'public' },
      { kind: 'email', value: 'kamola@metly.test', privacy: 'connections' },
      { kind: 'telegram', value: '@kamola', privacy: 'private' },
      { kind: 'website', value: 'https://kamola.uz', privacy: 'public' },
      { kind: 'linkedin', value: 'kamola', privacy: 'public' },
    ],
  },
  passTypeIdentifier: 'pass.app.nameshake.ios.card',
  teamIdentifier: 'TEAM123456',
  webServiceURL: 'https://api.metly.test/passkit',
  webBaseUrl: 'https://metly.test',
});

describe('buildPassJson', () => {
  it('lists Public extra phones after the primary phone on the back', () => {
    const base = input();
    const pass = buildPassJson({
      ...base,
      profile: {
        ...base.profile,
        additionalPhones: [
          { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a11', label: 'work', value: '+998 71 200 00 00', privacy: 'public' },
          { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a12', label: 'home', value: '+998 71 300 00 00', privacy: 'connections' },
        ],
      },
    });
    const back = (pass.generic as Record<string, { key: string; label?: string; value: string }[]>).backFields!;
    expect(back.slice(0, 3).map((f) => [f.key, f.label, f.value])).toEqual([
      ['back-phone', 'Phone', '+998901234567'],
      ['back-phone-1', 'Work', '+998 71 200 00 00'],
      ['back-website', 'Website', 'https://kamola.uz'],
    ]);
    expect(JSON.stringify(pass)).not.toContain('+998 71 300 00 00');
  });

  it('builds a generic pass with identity, web service and token', () => {
    const pass = buildPassJson(input());
    expect(pass).toMatchObject({
      formatVersion: 1,
      passTypeIdentifier: 'pass.app.nameshake.ios.card',
      teamIdentifier: 'TEAM123456',
      serialNumber: '7b0c2f3e-1d2a-4c5b-9e8f-0a1b2c3d4e5f',
      authenticationToken: 'token-token-token-token-1234',
      webServiceURL: 'https://api.metly.test/passkit',
      organizationName: 'Nameshake',
    });
    const generic = pass.generic as Record<string, { key: string; value: string }[]>;
    expect(generic.primaryFields![0]!.value).toBe('Kamola Yusupova');
    expect(generic.secondaryFields![0]!.value).toBe('Product Manager · Nameshake');
    expect(pass.voided).toBeUndefined();
  });

  it('shows Public ∩ visibleFields only', () => {
    const pass = buildPassJson(input());
    const generic = pass.generic as Record<string, { key: string; value: string }[]>;
    const values = [...generic.auxiliaryFields!, ...generic.backFields!].map((f) => f.value);
    expect(values).toContain('+998901234567');
    expect(values).toContain('https://kamola.uz');
    // connections-level, private, and public-but-not-visible fields never appear
    expect(values).not.toContain('kamola@metly.test');
    expect(values).not.toContain('@kamola');
    expect(values).not.toContain('kamola');
    expect(JSON.stringify(pass)).not.toContain('kamola@metly.test');
  });

  it('encodes the card URL as an ISO-8859-1 QR code', () => {
    const pass = buildPassJson(input());
    expect(pass.barcodes).toEqual([
      { format: 'PKBarcodeFormatQR', message: 'https://metly.test/c/kamola-ab12', messageEncoding: 'iso-8859-1', altText: 'metly.test/c/kamola-ab12' },
    ]);
    expect(buildPassJson(input({ slug: null })).barcodes).toBeUndefined();
  });

  it('uses the card palette colours', () => {
    const pass = buildPassJson(input());
    const colors = paletteColors({ palette: 'ink', appearance: 'dark' });
    expect(pass.backgroundColor).toBe('rgb(8, 17, 31)');
    expect(pass.foregroundColor).toBe(rgb(colors.foreground));
    expect(pass.labelColor).toBe('rgb(96, 165, 250)');
  });

  it('voids the pass of a deleted card and drops the barcode', () => {
    const pass = buildPassJson(input({ deletedAt: new Date() }));
    expect(pass.voided).toBe(true);
    expect(pass.barcodes).toBeUndefined();
  });

  it('omits an empty role', () => {
    const pass = buildPassJson(input({ jobTitle: '', company: ' ' }));
    expect((pass.generic as Record<string, unknown[]>).secondaryFields).toEqual([]);
  });
});
