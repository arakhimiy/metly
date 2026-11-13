import { describe, expect, it } from 'vitest';
import { LANGS, langFromLocale, pickLang, plural } from './lang';
import { PUSH_MESSAGES, type PushTextRef, renderPush, SHAREBACK_CONNECTION_TEXT } from './messages';
import { CARD_PAGE_TEXT, UNAVAILABLE_PAGE_TEXT } from './web-page';

describe('i18n', () => {
  it('maps device locales: uz and ru by language, other languages to English, nothing to Uzbek', () => {
    expect(langFromLocale('uz_UZ')).toBe('uz');
    expect(langFromLocale('uz-Cyrl_UZ')).toBe('uz');
    expect(langFromLocale('uz-Latn')).toBe('uz');
    expect(langFromLocale('ru_RU')).toBe('ru');
    expect(langFromLocale('ru_UZ')).toBe('ru');
    expect(langFromLocale('RU')).toBe('ru');
    expect(langFromLocale('en_US')).toBe('en');
    expect(langFromLocale('en_UZ')).toBe('en');
    expect(langFromLocale('de_DE')).toBe('en');
    expect(langFromLocale('tr')).toBe('en');
    expect(langFromLocale('')).toBe('uz');
    expect(langFromLocale('  ')).toBe('uz');
    expect(langFromLocale(null)).toBe('uz');
    expect(langFromLocale(undefined)).toBe('uz');
  });

  it('re-exports the web pages’ language picker', () => {
    expect(pickLang('ru', 'en-US')).toBe('ru');
    expect(pickLang(undefined, 'en-GB,en;q=0.9')).toBe('en');
    expect(pickLang(undefined, undefined)).toBe('uz');
  });

  it('picks Russian one/few/many and English one/other; Uzbek keeps the noun singular', () => {
    const ru = { one: 'контакт', few: 'контакта', many: 'контактов', other: 'контакта' };
    const pick = (n: number) => plural('ru', n, ru);
    expect([1, 21, 101].map(pick)).toEqual(['контакт', 'контакт', 'контакт']);
    expect([2, 3, 4, 22, 34].map(pick)).toEqual(Array(5).fill('контакта'));
    expect([0, 5, 11, 12, 13, 14, 19, 20, 25, 111, 112].map(pick)).toEqual(Array(11).fill('контактов'));
    expect(pick(1.5)).toBe('контакта');
    expect(plural('ru', 3, { one: 'a', other: 'b' })).toBe('b');
    expect(plural('en', 1, { one: 'person', other: 'people' })).toBe('person');
    expect(plural('en', 0, { one: 'person', other: 'people' })).toBe('people');
    expect(plural('uz', 3, { one: 'tanish', other: 'tanish' })).toBe('tanish');
  });

  it('has every push message in every language, without empty or untranslated texts', () => {
    const samples: PushTextRef[] = [
      { id: 'connectRequest', params: { name: 'Aziza', eventName: 'ICT Week' } },
      { id: 'connectRequest', params: { name: null, eventName: null } },
      { id: 'connectViaLink', params: { name: 'Aziza' } },
      { id: 'connectViaLink', params: { name: null } },
      { id: 'connectAccepted', params: { name: 'Aziza' } },
      { id: 'connectAccepted', params: { name: null } },
      { id: 'shareBackReceived', params: { name: 'Sardor', context: null } },
      { id: 'followUpDue', params: { personName: 'Sardor', title: 'x' } },
      { id: 'followUpDue', params: { personName: null, title: '' } },
      { id: 'eventSummary', params: { eventName: 'ICT Week', people: 2 } },
      { id: 'eventSummary', params: { eventName: ' ', people: 0 } },
    ];
    expect(new Set(samples.map((s) => s.id))).toEqual(new Set(Object.keys(PUSH_MESSAGES)));
    for (const sample of samples) {
      const en = renderPush(sample, 'en');
      for (const lang of LANGS) {
        const text = renderPush(sample, lang);
        expect(text.title.trim()).not.toBe('');
        expect(text.body.trim()).not.toBe('');
        if (lang !== 'en') expect(text.title).not.toBe(en.title);
      }
    }
  });

  it('renders the push texts', () => {
    const request: PushTextRef = { id: 'connectRequest', params: { name: 'Bobur', eventName: 'ICT Week' } };
    expect(renderPush(request, 'uz')).toEqual({ title: 'Bobur siz bilan vizitka almashmoqchi', body: 'ICT Week tadbirida' });
    expect(renderPush(request, 'ru')).toEqual({ title: 'Bobur хочет обменяться визитками', body: 'На мероприятии «ICT Week»' });
    expect(renderPush(request, 'en')).toEqual({ title: 'Bobur wants to swap cards', body: 'At ICT Week' });
    expect(renderPush({ id: 'connectAccepted', params: { name: null } }, 'en').title).toBe('You swapped cards');
    expect(renderPush({ id: 'shareBackReceived', params: { name: 'Sardor', context: 'ICT Week' } }, 'ru')).toEqual({
      title: 'Ответный контакт: Sardor',
      body: 'ICT Week',
    });
  });

  it('counts the people met in the event summary with the right plural form', () => {
    const body = (lang: 'uz' | 'ru' | 'en', people: number) => renderPush({ id: 'eventSummary', params: { eventName: 'ICT Week', people } }, lang).body;
    expect(body('en', 1)).toMatch(/^You met 1 person\./);
    expect(body('en', 2)).toMatch(/^You met 2 people\./);
    expect(body('ru', 1)).toMatch(/^1 новый контакт\./);
    expect(body('ru', 3)).toMatch(/^3 новых контакта\./);
    expect(body('ru', 5)).toMatch(/^5 новых контактов\./);
    expect(body('ru', 21)).toMatch(/^21 новый контакт\./);
    expect(body('uz', 1)).toMatch(/^1 ta yangi tanish\./);
    expect(body('uz', 7)).toMatch(/^7 ta yangi tanish\./);
    expect(renderPush({ id: 'eventSummary', params: { eventName: 'ICT Week', people: 0 } }, 'uz').title).toBe('«ICT Week» tadbiri yakunlandi');
    expect(renderPush({ id: 'eventSummary', params: { eventName: '', people: 0 } }, 'ru').title).toBe('Мероприятие завершено');
  });

  it('has the record and page texts in every language', () => {
    const shapes = (record: object) => JSON.stringify(Object.keys(record).sort());
    for (const lang of LANGS) {
      expect(SHAREBACK_CONNECTION_TEXT[lang].jobTitle).not.toBe('');
      expect(shapes(CARD_PAGE_TEXT[lang])).toBe(shapes(CARD_PAGE_TEXT.en));
      expect(shapes(CARD_PAGE_TEXT[lang].script)).toBe(shapes(CARD_PAGE_TEXT.en.script));
      for (const value of Object.values(CARD_PAGE_TEXT[lang].script)) expect(value.trim()).not.toBe('');
      expect(UNAVAILABLE_PAGE_TEXT[lang].notFound.title).not.toBe('');
    }
  });

  it('writes Uzbek with the typographic o‘ / g‘ and ’ — never ASCII quotes or backticks', () => {
    const uz = JSON.stringify([
      CARD_PAGE_TEXT.uz.script,
      UNAVAILABLE_PAGE_TEXT.uz,
      Object.values(CARD_PAGE_TEXT.uz).filter((v) => typeof v === 'string'),
      ...[null, 'Sardor'].map((personName) => renderPush({ id: 'followUpDue', params: { personName, title: '' } }, 'uz')),
      renderPush({ id: 'eventSummary', params: { eventName: '', people: 0 } }, 'uz'),
      renderPush({ id: 'connectAccepted', params: { name: null } }, 'uz'),
    ]);
    expect(uz).not.toMatch(/[ʻʼ`']/);
    expect(uz).not.toMatch(/[og][ʻ'`]/);
    expect(uz).toContain('o‘');
  });
});
