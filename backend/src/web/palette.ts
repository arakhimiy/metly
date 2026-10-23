import type { CardDesign } from '../records/wire';

// Card palettes, SPEC §4.2 — same values as MetlyCardKit `CardPalette+Colors.swift`.

type Rgb = [number, number, number];

const PALETTES: Record<string, { light: [number, number, number]; dark: [number, number, number] }> = {
  graphite: { light: [0xf5f5f7, 0x111114, 0x1c1c1e], dark: [0x0b0b0c, 0xf5f5f7, 0xffffff] },
  snow: { light: [0xffffff, 0x000000, 0x000000], dark: [0x000000, 0xffffff, 0xffffff] },
  ink: { light: [0xffffff, 0x0a1f44, 0x1d4ed8], dark: [0x08111f, 0xe8eef9, 0x60a5fa] },
  sand: { light: [0xf7f2ea, 0x2b2118, 0xa05a16], dark: [0x1a1410, 0xf5efe6, 0xf59e0b] },
  ocean: { light: [0xf0f9ff, 0x06283d, 0x0369a1], dark: [0x041b2b, 0xe0f2fe, 0x38bdf8] },
  ember: { light: [0xfff7f5, 0x3a1410, 0xc02626], dark: [0x1b0b08, 0xffede9, 0xf87171] },
};

const rgb = (hex: number): Rgb => [(hex >> 16) & 0xff, (hex >> 8) & 0xff, hex & 0xff];
const hex = ([r, g, b]: Rgb) => `#${[r, g, b].map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`;
/** `a` at `amount` mixed into `b` — CSS `color-mix(in srgb, a amount, b)`. */
const mix = (a: Rgb, b: Rgb, amount: number): Rgb => [0, 1, 2].map((i) => a[i]! * amount + b[i]! * (1 - amount)) as Rgb;

function luminance([r, g, b]: Rgb): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}
const contrast = (a: Rgb, b: Rgb) => {
  const [x, y] = [luminance(a), luminance(b)];
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

export interface PageColors {
  background: string;
  foreground: string;
  accent: string;
  muted: string;
  panelTint: string;
  gradientEnd: string;
  /** Foreground as `r, g, b` for rgba() rules and surfaces. */
  foregroundRgb: string;
  /** Text on an accent-filled button. */
  onAccent: string;
  dark: boolean;
}

export function pageColors(design: Pick<CardDesign, 'palette' | 'appearance'> | null): PageColors {
  const palette = PALETTES[design?.palette ?? 'graphite'] ?? PALETTES.graphite!;
  const dark = design?.appearance === 'dark';
  const [bgHex, fgHex, accHex] = dark ? palette.dark : palette.light;
  const bg = rgb(bgHex);
  const fg = rgb(fgHex);
  const acc = rgb(accHex);
  const white: Rgb = [255, 255, 255];
  const black: Rgb = [0, 0, 0];
  return {
    background: hex(bg),
    foreground: hex(fg),
    accent: hex(acc),
    muted: hex(mix(fg, bg, 0.66)),
    panelTint: hex(mix(acc, bg, 0.24)),
    gradientEnd: hex(mix(acc, bg, 0.4)),
    foregroundRgb: fg.join(', '),
    onAccent: contrast(acc, white) >= contrast(acc, black) ? '#ffffff' : '#000000',
    dark,
  };
}
