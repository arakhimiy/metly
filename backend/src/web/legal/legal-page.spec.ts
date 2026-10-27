import { describe, expect, it } from 'vitest';
import { LEGAL } from './legal-content';
import { pickLang, renderLegalPage } from './legal-page';

describe('legal pages', () => {
  it('picks the language from ?lang=, then Accept-Language, then Uzbek', () => {
    expect(pickLang('ru', 'en-US,en;q=0.9')).toBe('ru');
    expect(pickLang(undefined, 'ru-RU,ru;q=0.9,en;q=0.8')).toBe('ru');
    expect(pickLang(undefined, 'de-DE,en;q=0.5')).toBe('en');
    expect(pickLang('xx', undefined)).toBe('uz');
  });

  it('has the same sections in every language', () => {
    for (const doc of Object.values(LEGAL)) {
      expect(doc.uz.sections.length).toBe(doc.en.sections.length);
      expect(doc.ru.sections.length).toBe(doc.en.sections.length);
    }
  });

  it('renders every section and links the other languages', () => {
    const page = renderLegalPage('privacy', 'en');
    for (const section of LEGAL.privacy.en.sections) expect(page).toContain(section.heading);
    expect(page).toContain('href="/privacy?lang=uz"');
    expect(page).toContain('<html lang="en">');
    expect(page).not.toContain('<script');
  });
});
