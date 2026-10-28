import { describe, expect, it } from 'vitest';
import { contactAction, instagramUsername, linkedInUrl, telegramUsername, websiteUrl, whatsappUrl } from './contact-links';

describe('contact links', () => {
  it('phone → tel: with digits and a leading +', () => {
    expect(contactAction({ kind: 'phone', value: '+998 (90) 123-45-67', privacy: 'public' })).toMatchObject({
      href: 'tel:+998901234567',
      display: '+998 (90) 123-45-67',
      label: 'phone',
    });
  });

  it('email → mailto: only for plausible addresses', () => {
    expect(contactAction({ kind: 'email', value: 'a@b.uz', privacy: 'public' })?.href).toBe('mailto:a@b.uz');
    expect(contactAction({ kind: 'email', value: 'a@b"><x', privacy: 'public' })?.href).toBeNull();
  });

  it('telegram handles and links → https://t.me/…', () => {
    expect(telegramUsername('@kamola')).toBe('kamola');
    expect(telegramUsername('https://t.me/kamola?start=1')).toBe('kamola');
    expect(telegramUsername('t.me/kamola')).toBe('kamola');
    expect(telegramUsername('javascript:alert(1)')).toBeNull();
    expect(contactAction({ kind: 'telegram', value: 'kamola', privacy: 'public' })).toMatchObject({ href: 'https://t.me/kamola', display: '@kamola' });
  });

  it('website adds https and refuses other schemes', () => {
    expect(websiteUrl('tanishly.app/about')).toBe('https://tanishly.app/about');
    expect(websiteUrl('http://tanishly.app')).toBe('http://tanishly.app/');
    expect(websiteUrl('javascript:alert(1)') ?? 'https://').toMatch(/^https:\/\//);
    expect(websiteUrl('javascript://alert(1)')).toBeNull();
    expect(websiteUrl('ftp://x.y')).toBeNull();
    expect(contactAction({ kind: 'website', value: 'https://www.tanishly.app/', privacy: 'public' })?.display).toBe('tanishly.app');
  });

  it('linkedin builds profile URLs', () => {
    expect(linkedInUrl('in/kamola')).toBe('https://www.linkedin.com/in/kamola');
    expect(linkedInUrl('kamola')).toBe('https://www.linkedin.com/in/kamola');
    expect(linkedInUrl('linkedin.com/in/kamola')).toBe('https://linkedin.com/in/kamola');
    expect(contactAction({ kind: 'linkedin', value: 'kamola', privacy: 'public' })?.display).toBe('in/kamola');
  });

  it('whatsapp links wa.me with the digits only', () => {
    expect(whatsappUrl('+998 (90) 123-45-67')).toBe('https://wa.me/998901234567');
    expect(whatsappUrl('12')).toBeNull();
    expect(contactAction({ kind: 'whatsapp', value: '+998 90 123 45 67' })).toMatchObject({
      display: '+998 90 123 45 67',
      href: 'https://wa.me/998901234567',
      key: 'wa',
    });
  });

  it('instagram accepts @user, user and instagram.com URLs', () => {
    expect(instagramUsername('@kamola.y')).toBe('kamola.y');
    expect(instagramUsername('kamola_y')).toBe('kamola_y');
    expect(instagramUsername('https://www.instagram.com/kamola.y/?hl=en')).toBe('kamola.y');
    expect(instagramUsername('instagram.com/kamola')).toBe('kamola');
    expect(instagramUsername('not a handle')).toBeNull();
    expect(contactAction({ kind: 'instagram', value: 'instagram.com/kamola' })).toMatchObject({ display: '@kamola', href: 'https://instagram.com/kamola' });
    expect(contactAction({ kind: 'instagram', value: 'bad handle!' })).toMatchObject({ display: 'bad handle!', href: null });
  });

  it('empty values have no action', () => {
    expect(contactAction({ kind: 'phone', value: '  ', privacy: 'public' })).toBeNull();
  });
});
