import { describe, expect, it } from 'vitest';
import {
  cardContacts,
  cardContactsView,
  connectionContactData,
  connectionContacts,
  contactKey,
  contactsToLegacy,
  legacyToContacts,
  mergeContacts,
  PRIMARY_CONTACT_IDS,
  profileContactData,
  profileContacts,
  storedContacts,
} from './contacts';
import { type CardDesign, ConnectionIn, type ContactEntry, MAX_CONTACTS, ProfileIn } from './wire';

const id = (n: number) => `6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a${String(n).padStart(2, '0')}`;
const entry = (n: number, kind: ContactEntry['kind'], value: string, privacy: ContactEntry['privacy'] = 'public', label: ContactEntry['label'] = null) => ({
  id: id(n),
  kind,
  label: kind === 'phone' ? (label ?? 'mobile') : null,
  value,
  privacy,
});

const mobile = entry(1, 'phone', '+998 90 123 45 67', 'public');
const whatsapp = entry(2, 'whatsapp', '+998 90 123 45 67', 'connections');
const work = entry(3, 'phone', '+998 71 200 00 00', 'connections', 'work');
const email = entry(4, 'email', 'kamola@metly.uz', 'public');
const instagram = entry(5, 'instagram', '@kamola.y', 'public');
const email2 = entry(6, 'email', 'k@work.uz', 'private');
const telegram = entry(7, 'telegram', '@kamola', 'public');
const list: ContactEntry[] = [mobile, whatsapp, work, email, instagram, email2, telegram];

describe('storedContacts', () => {
  it('reads defensively: bad kinds, empty values, repeated ids dropped; labels normalised; never throws', () => {
    const stored = storedContacts([
      mobile,
      { ...whatsapp, label: 'work' },
      { id: id(9), kind: 'fax', label: null, value: '1', privacy: 'public' },
      { ...email, value: '   ' },
      { ...work, id: mobile.id },
      { ...work, label: 'pager', privacy: 'secret' },
      42,
      null,
    ]);
    expect(stored).toEqual([mobile, whatsapp, { ...work, label: 'mobile', privacy: 'connections' }]);
    expect(storedContacts(null)).toEqual([]);
    expect(storedContacts({ not: 'an array' })).toEqual([]);
  });

  it('cuts over-long values and keeps at most 10', () => {
    const many = Array.from({ length: 12 }, (_, i) => entry(20 + i, 'email', `a${i}@b.uz`));
    expect(storedContacts(many)).toHaveLength(MAX_CONTACTS);
    expect(storedContacts([{ ...mobile, value: '1'.repeat(60) }])[0]!.value).toHaveLength(40);
  });
});

describe('list → legacy', () => {
  it('first entry of each legacy kind, label of the first phone, the other phones as extras', () => {
    const legacy = contactsToLegacy(list);
    expect(legacy.contactFields).toEqual([
      { kind: 'phone', value: mobile.value, privacy: 'public' },
      { kind: 'email', value: email.value, privacy: 'public' },
      { kind: 'telegram', value: telegram.value, privacy: 'public' },
      { kind: 'website', value: '', privacy: 'public' },
      { kind: 'linkedin', value: '', privacy: 'connections' },
    ]);
    expect(legacy.phoneLabel).toBe('mobile');
    expect(legacy.additionalPhones).toEqual([{ id: work.id, label: 'work', value: work.value, privacy: 'connections' }]);
    expect(contactsToLegacy([work]).phoneLabel).toBe('work');
    expect(contactsToLegacy([]).phoneLabel).toBe('mobile');
  });

  it('caps the extras at 5', () => {
    const phones = Array.from({ length: 8 }, (_, i) => entry(30 + i, 'phone', `+1 555 000 00 0${i}`));
    expect(contactsToLegacy(phones).additionalPhones).toHaveLength(5);
  });

  it('writes the columns of a profile and of a connection', () => {
    expect(profileContactData(list)).toMatchObject({ contacts: list, phoneLabel: 'mobile' });
    expect(connectionContactData(list)).toMatchObject({
      contacts: list,
      phone: mobile.value,
      email: email.value,
      telegram: telegram.value,
      website: '',
      linkedin: '',
      phoneLabel: 'mobile',
    });
  });
});

describe('legacy → list', () => {
  const primary = {
    phone: { value: '+998 90 999 99 99', privacy: 'public' as const },
    email: { value: 'new@metly.uz', privacy: 'connections' as const },
    linkedin: { value: 'in/kamola', privacy: 'public' as const },
  };

  it('rebuilds what the legacy fields express, then appends the kept entries in stored order', () => {
    const rebuilt = legacyToContacts(
      { primary, phoneLabel: 'home', additionalPhones: [{ id: work.id, label: 'work', value: work.value, privacy: 'public' }] },
      list,
    );
    expect(rebuilt.map((e) => [e.kind, e.value])).toEqual([
      ['phone', '+998 90 999 99 99'],
      ['phone', work.value],
      ['email', 'new@metly.uz'],
      ['linkedin', 'in/kamola'],
      ['whatsapp', whatsapp.value],
      ['instagram', instagram.value],
      ['email', email2.value],
    ]);
    // The primary phone keeps the id of the phone it replaces; extras keep theirs; the first email
    // keeps its id; a new linkedin gets the fixed one. The stored telegram is gone (old app cleared it).
    expect(rebuilt[0]).toMatchObject({ id: mobile.id, label: 'home', privacy: 'public' });
    expect(rebuilt[1]).toMatchObject({ id: work.id, label: 'work', privacy: 'public' });
    expect(rebuilt[2]!.id).toBe(email.id);
    expect(rebuilt[3]!.id).toBe(PRIMARY_CONTACT_IDS.linkedin);
    expect(rebuilt.slice(4)).toEqual([whatsapp, instagram, email2]);
  });

  it('without a stored list uses the fixed primary ids (a row from before the list)', () => {
    const rebuilt = legacyToContacts({ primary: { ...primary, telegram: { value: '@k', privacy: 'public' } }, phoneLabel: 'mobile', additionalPhones: [] });
    expect(rebuilt.map((e) => e.id)).toEqual([
      PRIMARY_CONTACT_IDS.phone,
      PRIMARY_CONTACT_IDS.email,
      PRIMARY_CONTACT_IDS.telegram,
      PRIMARY_CONTACT_IDS.linkedin,
    ]);
    expect(rebuilt.every((e) => (e.kind === 'phone' ? e.label === 'mobile' : e.label === null))).toBe(true);
  });

  it('skips empty values, never repeats an id and caps at 10', () => {
    const extras = Array.from({ length: 5 }, (_, i) => ({ id: id(40 + i), label: 'other' as const, value: `+1 555 00${i}`, privacy: 'public' as const }));
    extras.push({ ...extras[0]!, value: '+1 555 999' });
    const rebuilt = legacyToContacts(
      { primary: { phone: { value: '  ', privacy: 'public' }, email: primary.email }, phoneLabel: 'mobile', additionalPhones: extras },
      [...list, entry(50, 'website', 'kamola.uz'), entry(51, 'instagram', '@two'), entry(52, 'instagram', '@three'), entry(53, 'whatsapp', '+1 2')],
    );
    expect(rebuilt).toHaveLength(MAX_CONTACTS);
    expect(new Set(rebuilt.map((e) => e.id)).size).toBe(rebuilt.length);
    expect(rebuilt[0]!.value).toBe('+1 555 000');
  });

  it('a profile row stored before the list reads as the list built from its legacy columns', () => {
    const row = {
      contacts: [],
      contactFields: [
        { kind: 'phone', value: '+998901234567', privacy: 'public' },
        { kind: 'email', value: '', privacy: 'public' },
        { kind: 'telegram', value: '@kamola', privacy: 'private' },
      ],
      phoneLabel: 'work',
      additionalPhones: [{ id: work.id, label: 'home', value: work.value, privacy: 'connections' }],
    };
    expect(profileContacts(row)).toEqual([
      { id: PRIMARY_CONTACT_IDS.phone, kind: 'phone', label: 'work', value: '+998901234567', privacy: 'public' },
      { id: work.id, kind: 'phone', label: 'home', value: work.value, privacy: 'connections' },
      { id: PRIMARY_CONTACT_IDS.telegram, kind: 'telegram', label: null, value: '@kamola', privacy: 'private' },
    ]);
    // Once it has a list, the list wins.
    expect(profileContacts({ ...row, contacts: [instagram] })).toEqual([instagram]);
  });

  it('a connection row stored before the list reads as its columns (Connections-level)', () => {
    const row = { contacts: [], phone: '+998907654321', phoneLabel: 'mobile', additionalPhones: [], email: '', telegram: '@sardor', website: 'acme.uz', linkedin: '' };
    expect(connectionContacts(row).map((e) => [e.id, e.kind, e.value, e.privacy])).toEqual([
      [PRIMARY_CONTACT_IDS.phone, 'phone', '+998907654321', 'connections'],
      [PRIMARY_CONTACT_IDS.telegram, 'telegram', '@sardor', 'connections'],
      [PRIMARY_CONTACT_IDS.website, 'website', 'acme.uz', 'connections'],
    ]);
  });
});

describe('cards', () => {
  const legacyCard = { visibleFields: ['phone', 'email'] } as CardDesign;

  it('a legacy card shows every entry of its visibleFields kinds — never WhatsApp/Instagram — by audience', () => {
    expect(cardContacts(list, legacyCard, 'public')).toEqual([mobile, email]);
    expect(cardContacts(list, legacyCard, 'connections')).toEqual([mobile, work, email]);
  });

  it('a selection shows its entries in profile order; unknown ids ignored; Private never', () => {
    const design = { visibleFields: ['email'], visibleContacts: [instagram.id, email2.id, whatsapp.id, id(99), email.id] } as CardDesign;
    expect(cardContacts(list, design, 'public')).toEqual([email, instagram]);
    expect(cardContacts(list, design, 'connections')).toEqual([whatsapp, email, instagram]);
    expect(cardContacts(list, { ...design, visibleContacts: [] }, 'connections')).toEqual([]);
  });

  it('derives the legacy fields from the visible entries', () => {
    const design = { visibleFields: ['phone'], visibleContacts: [work.id, whatsapp.id, email.id, telegram.id] } as CardDesign;
    const view = cardContactsView({ contacts: list, contactFields: [] }, design, 'connections');
    expect(view.contacts).toEqual([whatsapp, work, email, telegram]);
    expect(view.fields).toEqual([
      { kind: 'phone', value: work.value, privacy: 'connections' },
      { kind: 'email', value: email.value, privacy: 'public' },
      { kind: 'telegram', value: telegram.value, privacy: 'public' },
    ]);
    expect(view.phoneLabel).toBe('work');
    expect(view.additionalPhones).toEqual([]);
    // The phone hidden: its label is still sent.
    expect(cardContactsView({ contacts: list, contactFields: [] }, { ...design, visibleContacts: [email.id] }, 'public').phoneLabel).toBe('mobile');
  });
});

describe('mergeContacts', () => {
  it('skips entries already there (digits / handle / lower-cased), appends new ones Connections-level', () => {
    const merged = mergeContacts(
      [mobile, telegram],
      [
        entry(60, 'phone', '998901234567', 'public', 'work'),
        entry(61, 'telegram', 'https://t.me/KAMOLA'),
        entry(62, 'whatsapp', '+998 90 123 45 67', 'public'),
        entry(63, 'instagram', 'instagram.com/Kamola.Y'),
        entry(64, 'instagram', '@kamola.y'),
        entry(65, 'email', ' '),
      ],
    );
    expect(merged.changed).toBe(true);
    expect(merged.added.map((e) => [e.kind, e.value, e.privacy])).toEqual([
      ['whatsapp', '+998 90 123 45 67', 'connections'],
      ['instagram', 'instagram.com/Kamola.Y', 'connections'],
    ]);
    expect(merged.contacts).toHaveLength(4);
    expect(merged.contacts[0]!.label).toBe('mobile');
  });

  it('adopts the label of the same number when asked; keeps ids unless taken; caps at 10', () => {
    expect(mergeContacts([mobile], [entry(70, 'phone', '+998901234567', 'public', 'home')], { adoptLabel: true }).contacts[0]!.label).toBe('home');
    expect(mergeContacts([mobile], [{ ...work, id: mobile.id }]).added[0]!.id).not.toBe(mobile.id);
    expect(mergeContacts([], [work]).added[0]!.id).toBe(work.id);
    const many = Array.from({ length: 12 }, (_, i) => entry(71 + i, 'email', `x${i}@y.uz`));
    expect(mergeContacts([mobile], many).contacts).toHaveLength(MAX_CONTACTS);
    expect(mergeContacts([mobile], [mobile]).changed).toBe(false);
  });

  it('keys by kind: the same digits as phone and as WhatsApp are different entries', () => {
    expect(contactKey(mobile)).toBe('phone:998901234567');
    expect(contactKey(whatsapp)).toBe('whatsapp:998901234567');
    expect(contactKey(entry(80, 'website', 'HTTPS://www.Kamola.uz/'))).toBe(contactKey(entry(81, 'website', 'kamola.uz')));
    expect(contactKey(entry(82, 'phone', 'ext'))).toBe('');
  });
});

describe('wire', () => {
  const base = { id: id(90), createdAt: '2026-09-26T10:00:00Z', updatedAt: '2026-09-26T10:00:00Z' };
  const profile = {
    ...base,
    fullName: 'Kamola',
    jobTitle: '',
    company: '',
    contactFields: [],
    linksPaused: false,
    notificationPrefs: {
      followUpReminders: true,
      eventSummary: true,
      delivery: 'push',
      connectRequests: true,
      cardSaved: true,
      weeklySummary: false,
      productNews: false,
    },
    privacySettings: { findByEmail: true, showInNearby: true, shareAnalytics: true },
    isSetupComplete: true,
  };
  const connection = {
    ...base,
    fullName: 'Sardor',
    jobTitle: '',
    company: '',
    phone: '',
    email: '',
    telegram: '',
    website: '',
    linkedin: '',
    source: 'paper',
    context: { metAt: '2026-09-26T10:00:00Z' },
    previousMeetings: [],
    note: '',
    tags: [],
    isMerged: false,
    isPendingMerge: false,
    isBlocked: false,
  };

  it('absent or null contacts stay undefined (an older app)', () => {
    expect(ProfileIn.parse(profile).contacts).toBeUndefined();
    expect(ProfileIn.parse({ ...profile, contacts: null }).contacts).toBeUndefined();
    expect(ConnectionIn.parse(connection).contacts).toBeUndefined();
  });

  it('trims values, lower-cases ids, nulls the label of non-phones, defaults a phone label to mobile', () => {
    const parsed = ProfileIn.parse({
      ...profile,
      contacts: [
        { id: id(1).toUpperCase(), kind: 'phone', value: ' +998 90 ', privacy: 'public' },
        { id: id(2), kind: 'whatsapp', label: 'work', value: '+998 90', privacy: 'connections' },
      ],
    });
    expect(parsed.contacts).toEqual([
      { id: id(1), kind: 'phone', label: 'mobile', value: '+998 90', privacy: 'public' },
      { id: id(2), kind: 'whatsapp', label: null, value: '+998 90', privacy: 'connections' },
    ]);
    // On a connection the privacy may be omitted.
    expect(ConnectionIn.parse({ ...connection, contacts: [{ id: id(3), kind: 'instagram', value: '@s' }] }).contacts![0]!.privacy).toBe('connections');
  });

  it('rejects 11 entries, unknown kinds, empty or over-long values, bad phone labels, duplicate ids', () => {
    const ok = (contacts: unknown) => ProfileIn.safeParse({ ...profile, contacts }).success;
    expect(ok(Array.from({ length: 10 }, (_, i) => entry(i, 'email', `a${i}@b.uz`)))).toBe(true);
    expect(ok(Array.from({ length: 11 }, (_, i) => entry(i, 'email', `a${i}@b.uz`)))).toBe(false);
    expect(ok([{ ...email, kind: 'fax' }])).toBe(false);
    expect(ok([{ ...email, value: '  ' }])).toBe(false);
    expect(ok([{ ...mobile, value: '1'.repeat(41) }])).toBe(false);
    expect(ok([{ ...whatsapp, value: '1'.repeat(41) }])).toBe(false);
    expect(ok([{ ...email, value: `${'a'.repeat(196)}@b.uz` }])).toBe(false);
    expect(ok([{ ...entry(1, 'website', `https://${'a'.repeat(480)}.uz`) }])).toBe(true);
    expect(ok([{ ...mobile, label: 'fax' }])).toBe(false);
    expect(ok([mobile, { ...email, id: mobile.id }])).toBe(false);
    expect(ok([{ ...email, privacy: 'friends' }])).toBe(false);
  });
});
