import { describe, expect, it } from 'vitest';
import { cardSnapshot } from '../records/snapshot';
import { CardDesign, cardIdentity, PRO_TEMPLATES } from '../records/wire';
import { renderCardPage } from './page';
import type { PublicView } from './public-card.service';

// Card templates v2 (docs/design/card-templates-v2.md): per-card switches and the HTML mirror of the faces.

const baseDesign = {
  template: 'minimal',
  palette: 'ink',
  appearance: 'dark',
  font: 'system',
  alignment: 'leading',
  density: 'balanced',
  background: 'solid',
  showQR: true,
  showPhoto: true,
  showLogo: true,
  visibleFields: ['phone'],
} as const;

describe('card design face options', () => {
  it('accepts designs from older apps and stores only switches that are off', () => {
    expect(CardDesign.parse(baseDesign)).toEqual({ ...baseDesign, visibleFields: ['phone'] });
    const shown = CardDesign.parse({ ...baseDesign, showJobTitle: true, showCompany: true, logoStyle: 'original' });
    expect(shown).not.toHaveProperty('showJobTitle');
    expect(shown).not.toHaveProperty('logoStyle');
    const hidden = CardDesign.parse({ ...baseDesign, showJobTitle: false, showCompany: false, logoStyle: 'mono' });
    expect(hidden).toMatchObject({ showJobTitle: false, showCompany: false, logoStyle: 'mono' });
  });

  it('rejects an unknown logo style', () => {
    expect(CardDesign.safeParse({ ...baseDesign, logoStyle: 'neon' }).success).toBe(false);
  });

  it('blanks a hidden job title or company', () => {
    const profile = { jobTitle: 'Designer', company: 'Tezkor' };
    expect(cardIdentity(profile, { showJobTitle: false })).toEqual({ jobTitle: '', company: 'Tezkor' });
    expect(cardIdentity(profile, { showCompany: false })).toEqual({ jobTitle: 'Designer', company: '' });
    expect(cardIdentity(profile, undefined)).toEqual(profile);
  });

  it('never sends what the owner hid in a shared card snapshot', () => {
    const card = { name: 'Work', slug: null, design: { ...baseDesign, showCompany: false } };
    const profile = { fullName: 'Kamola Karimova', jobTitle: 'Designer', company: 'Tezkor', contacts: [] };
    const snapshot = cardSnapshot(card as never, profile as never, 'public', 'https://x.test');
    expect(snapshot.company).toBe('');
    expect(snapshot.jobTitle).toBe('Designer');
  });

  it('makes the finish templates Pro', () => {
    expect([...PRO_TEMPLATES].sort()).toEqual(['editorial', 'gradient', 'modern']);
  });
});

describe('card page face', () => {
  const view = (template: string, extra: Record<string, unknown> = {}) =>
    ({
      slug: 'kamola-k',
      url: 'https://tanishly.test/c/kamola-k',
      profile: { jobTitle: 'Designer', company: 'Tezkor' },
      design: { ...baseDesign, template },
      contacts: [],
      fullName: 'Kamola Karimova',
      firstName: 'Kamola',
      photoUrl: null,
      logoUrl: 'https://cdn.test/logo.png',
      ...extra,
    }) as unknown as PublicView;
  const render = (v: PublicView) => renderCardPage({ view: v, nonce: 'n0nce', platform: 'ios', lang: 'en', appAvailable: true });

  it.each(['minimal', 'professional', 'modern', 'bold', 'gradient', 'split', 'terminal', 'stack', 'editorial'])(
    'renders the %s template with the name as the heading',
    (template) => {
      const html = render(view(template));
      expect(html).toContain(`class="face tpl-${template} `);
      expect(html).toContain('Kamola Karimova');
      expect(html).not.toMatch(/<section class="face[^"]*" style=/);
    },
  );

  it('puts the finish colours in the nonce’d style block', () => {
    const html = render(view('modern'));
    expect(html).toMatch(/\.face\{--foil:linear-gradient/);
    expect(render(view('gradient'))).toContain('--a1:#7c3aed');
  });

  it('shows the logo on every template with a logo slot', () => {
    for (const template of ['minimal', 'professional', 'split', 'stack', 'editorial']) {
      expect(render(view(template))).toContain('src="https://cdn.test/logo.png"');
    }
  });

  it('leaves out a company the card hides', () => {
    const html = render(view('minimal', { profile: { jobTitle: 'Designer', company: '' } }));
    expect(html).not.toContain('>Tezkor<');
    expect(html).toContain('Designer');
  });
});
