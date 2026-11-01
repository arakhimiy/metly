import { describe, expect, it } from 'vitest';
import { uzDative } from '../i18n/web-page';
import { type CardPageOptions, renderCardPage } from './page';
import type { PublicView } from './public-card.service';

const view = {
  slug: 'kamola-k',
  url: 'https://tanishly.test/c/kamola-k',
  profile: { jobTitle: 'Designer', company: 'Tezkor' },
  design: {
    template: 'minimal',
    palette: 'graphite',
    appearance: 'light',
    font: 'system',
    alignment: 'leading',
    density: 'balanced',
    background: 'solid',
    showQR: true,
    showPhoto: false,
    showLogo: false,
    visibleFields: ['phone'],
  },
  contacts: [],
  fullName: 'Kamola Karimova',
  firstName: 'Kamola',
  photoUrl: null,
  logoUrl: null,
} as unknown as PublicView;

const page = (opts: Partial<CardPageOptions> = {}) =>
  renderCardPage({ view, nonce: 'n0nce', platform: 'ios', lang: 'uz', appAvailable: true, ...opts });

describe('card page: "Want a card like this?"', () => {
  it('links the foot and the thank-you sheet to "Get the app" with their campaign', () => {
    const html = page();
    expect(html).toContain('href="/c/kamola-k/get-app?from=footer" data-get-app>Bepul yaratish</a>');
    expect(html).toContain('href="/c/kamola-k/get-app?from=shareback" data-get-app>Bepul yaratish</a>');
    expect(html).toContain('Sizga ham shunday karta kerakmi?');
    expect(html).toContain('Tanishly bilan 1 daqiqada yarating. Tanishganlaringiz hech qachon yo‘qolmaydi.');
  });

  it('speaks the page language', () => {
    expect(page({ lang: 'ru' })).toContain('Хотите такую же визитку?');
    expect(page({ lang: 'ru' })).toContain('>Создать бесплатно</a>');
    expect(page({ lang: 'en' })).toContain('Create yours with Tanishly in 1 minute. Never lose a new contact again.');
    expect(page({ lang: 'en' })).toContain('>Create for free</a>');
  });

  it('is left out when there is no app to download yet', () => {
    expect(page({ appAvailable: false })).not.toContain('class="cta"');
  });

  it('marks Android visitors; "Notify me" only once the bot’s waitlist exists', () => {
    expect(page()).toContain('<body class="p-ios" ');
    const noBot = page({ platform: 'inapp', android: true });
    expect(noBot).toContain('<body class="p-inapp os-android" ');
    expect(noBot).toContain('<span class="android">Hozircha faqat iPhone uchun.</span>');
    expect(noBot).not.toContain('Xabar olish');

    const withBot = page({ platform: 'android', android: true, androidWaitlistUrl: 'https://t.me/TanishlyBot?start=android' });
    expect(withBot).toContain('<span class="android">Hozircha faqat iPhone uchun. Android chiqqanda xabar beramiz.</span>');
    expect(withBot).toContain('<a class="btn android" href="https://t.me/TanishlyBot?start=android" target="_blank" rel="noopener noreferrer">Xabar olish</a>');
  });

  it('adds the Smart App Banner only with an App Store id', () => {
    expect(page()).not.toContain('apple-itunes-app');
    expect(page({ appStoreId: '6827516902' })).toContain(
      '<meta name="apple-itunes-app" content="app-id=6827516902, app-argument=https://tanishly.test/c/kamola-k">',
    );
  });
});

describe('card page: who receives a share-back', () => {
  it('names the owner above the button, on the button and after sending', () => {
    const html = page();
    expect(html).toContain('Kontaktingiz Kamolaga yuboriladi. Faqat u ko‘radi.');
    expect(html).toContain('>Kontaktimni yuborish</button>');
    expect(html).toContain('Kontaktingiz Kamolaga yuborildi');
  });

  it('says "the card owner" when the card shows no first name', () => {
    const nameless = { ...view, firstName: '' } as PublicView;
    expect(page({ view: nameless })).toContain('Kontaktingiz karta egasiga yuboriladi.');
    expect(page({ view: nameless, lang: 'ru' })).toContain('Ваш контакт получит владелец визитки.');
    expect(page({ view: nameless, lang: 'en' })).toContain('Your contact will be sent to the card owner.');
  });
});

describe('uzDative', () => {
  it('spells -ga / -ka / -qa after the last letter, Latin or Cyrillic', () => {
    expect(uzDative('Kamola')).toBe('Kamolaga');
    expect(uzDative('Malik')).toBe('Malikka');
    expect(uzDative('Tohir Oq')).toBe('Tohir Oqqa');
    expect(uzDative('Камола')).toBe('Камолага');
    expect(uzDative('Бек')).toBe('Бекка');
    expect(uzDative('karta egasi')).toBe('karta egasiga');
  });
});
