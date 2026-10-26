import type { Card, Profile } from '../../generated/prisma/client';
import { cardUrl } from '../../records/mappers';
import { visibleFields } from '../../records/snapshot';
import type { CardDesign, ContactField, ContactFieldKind } from '../../records/wire';

/**
 * Card palettes, `[background, foreground, accent]` per appearance — the same table as the app
 * (`MetlyCardKit/Palette/CardPalette+Colors.swift`, SPEC §4.2).
 */
const PALETTES: Record<CardDesign['palette'], Record<CardDesign['appearance'], [number, number, number]>> = {
  graphite: { light: [0xf5f5f7, 0x111114, 0x1c1c1e], dark: [0x0b0b0c, 0xf5f5f7, 0xffffff] },
  snow: { light: [0xffffff, 0x000000, 0x000000], dark: [0x000000, 0xffffff, 0xffffff] },
  ink: { light: [0xffffff, 0x0a1f44, 0x1d4ed8], dark: [0x08111f, 0xe8eef9, 0x60a5fa] },
  sand: { light: [0xf7f2ea, 0x2b2118, 0xa05a16], dark: [0x1a1410, 0xf5efe6, 0xf59e0b] },
  ocean: { light: [0xf0f9ff, 0x06283d, 0x0369a1], dark: [0x041b2b, 0xe0f2fe, 0x38bdf8] },
  ember: { light: [0xfff7f5, 0x3a1410, 0xc02626], dark: [0x1b0b08, 0xffede9, 0xf87171] },
};

export interface PassColors {
  background: number;
  foreground: number;
  accent: number;
}

export function paletteColors(design: Pick<CardDesign, 'palette' | 'appearance'>): PassColors {
  const [background, foreground, accent] = (PALETTES[design.palette] ?? PALETTES.graphite)[design.appearance] ?? PALETTES.graphite.light;
  return { background, foreground, accent };
}

export const rgb = (hex: number) => `rgb(${(hex >> 16) & 0xff}, ${(hex >> 8) & 0xff}, ${hex & 0xff})`;
export const hexString = (hex: number) => `#${hex.toString(16).padStart(6, '0')}`;

const LABELS: Record<ContactFieldKind, string> = {
  phone: 'Phone',
  email: 'Email',
  telegram: 'Telegram',
  website: 'Website',
  linkedin: 'LinkedIn',
};

export interface PassInput {
  card: Pick<Card, 'id' | 'name' | 'slug' | 'design' | 'passAuthToken' | 'deletedAt'>;
  profile: Pick<Profile, 'fullName' | 'jobTitle' | 'company' | 'contactFields'>;
  passTypeIdentifier: string;
  teamIdentifier: string;
  /** `${API_BASE_URL}/passkit` */
  webServiceURL: string;
  webBaseUrl: string;
}

interface PassField {
  key: string;
  label?: string;
  value: string;
  dataDetectorTypes?: string[];
}

function fieldValue(field: ContactField): string {
  return field.value.trim();
}

/**
 * pass.json of a Generic pass for a card. Shows **Public** fields only — a pass can leave the device
 * (AirDrop, Mail), so Connections/Private fields never appear (`visibleFields(…, 'public')`).
 * A deleted card yields a voided pass without a barcode.
 */
export function buildPassJson(input: PassInput): Record<string, unknown> {
  const { card, profile } = input;
  const design = card.design as CardDesign;
  const colors = paletteColors(design);
  const fields = visibleFields(profile, design, 'public');
  const role = [profile.jobTitle.trim(), profile.company.trim()].filter(Boolean).join(' · ');
  const url = card.slug ? cardUrl(input.webBaseUrl, card.slug) : null;
  const voided = card.deletedAt !== null;

  const auxiliaryFields: PassField[] = fields.slice(0, 3).map((f) => ({ key: `aux-${f.kind}`, label: LABELS[f.kind], value: fieldValue(f) }));
  const backFields: PassField[] = fields.map((f) => ({
    key: `back-${f.kind}`,
    label: LABELS[f.kind],
    value: fieldValue(f),
    dataDetectorTypes: f.kind === 'phone' ? ['PKDataDetectorTypePhoneNumber'] : f.kind === 'telegram' ? [] : ['PKDataDetectorTypeLink'],
  }));
  if (url) backFields.push({ key: 'card-url', label: 'Card', value: url, dataDetectorTypes: ['PKDataDetectorTypeLink'] });
  backFields.push({ key: 'about', label: 'Tanishly', value: 'This pass updates automatically when the card changes.' });

  const name = profile.fullName.trim() || card.name;
  return {
    formatVersion: 1,
    passTypeIdentifier: input.passTypeIdentifier,
    teamIdentifier: input.teamIdentifier,
    serialNumber: card.id,
    authenticationToken: card.passAuthToken,
    webServiceURL: input.webServiceURL,
    organizationName: 'Tanishly',
    description: `${name} — Tanishly card`,
    logoText: 'Tanishly',
    backgroundColor: rgb(colors.background),
    foregroundColor: rgb(colors.foreground),
    labelColor: rgb(colors.accent),
    sharingProhibited: false,
    ...(voided ? { voided: true } : {}),
    ...(url && !voided ? { barcodes: [{ format: 'PKBarcodeFormatQR', message: url, messageEncoding: 'iso-8859-1', altText: url.replace(/^https?:\/\//, '') }] } : {}),
    generic: {
      primaryFields: [{ key: 'name', label: card.name.trim() || 'Card', value: name }],
      ...(role ? { secondaryFields: [{ key: 'role', label: 'Role', value: role }] } : { secondaryFields: [] }),
      auxiliaryFields,
      backFields,
    },
  };
}
