import { describe, expect, it } from 'vitest';
import { mergePhones, phoneDigits, storedPhoneLabel, storedPhones, visiblePhones } from './phones';
import { type CardDesign, ConnectionIn, type LabeledPhone, ProfileIn } from './wire';

const design = { visibleFields: ['phone', 'email'] } as CardDesign;
const work: LabeledPhone = { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a11', label: 'work', value: '+998 71 200 00 00', privacy: 'public' };
const home: LabeledPhone = { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a12', label: 'home', value: '+998 71 300 00 00', privacy: 'connections' };
const secret: LabeledPhone = { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a13', label: 'other', value: '+998 71 400 00 00', privacy: 'private' };

describe('stored phones', () => {
  it('reads defensively: bad entries dropped, unknown labels → mobile', () => {
    expect(storedPhones([work, { label: 'work' }, 42, { ...home, privacy: 'nope' }])).toEqual([work, { ...home, privacy: 'connections' }]);
    expect(storedPhones(null)).toEqual([]);
    expect(storedPhoneLabel('home')).toBe('home');
    expect(storedPhoneLabel('fax')).toBe('mobile');
  });

  it('visibility follows the card: only with phones visible; Public, + Connections for mutual; never Private', () => {
    const blank = { ...work, id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a14', value: ' ' };
    const profile = { additionalPhones: [work, home, secret, blank] };
    expect(visiblePhones(profile, design, 'public')).toEqual([work]);
    expect(visiblePhones(profile, design, 'connections')).toEqual([work, home]);
    expect(visiblePhones(profile, { visibleFields: ['email'] } as CardDesign, 'connections')).toEqual([]);
  });
});

describe('mergePhones', () => {
  const empty = { phone: '', phoneLabel: 'mobile' as const, additionalPhones: [] };

  it('fills an empty phone (first number, else the first extra) and appends new numbers as Connections-level', () => {
    const a = mergePhones(empty, { phone: '+998 90 555 12 34', phoneLabel: 'work', additionalPhones: [work] });
    expect(a).toMatchObject({ changed: true, phone: '+998 90 555 12 34', phoneLabel: 'work' });
    expect(a.additionalPhones).toEqual([{ ...work, privacy: 'connections' }]);

    const b = mergePhones(empty, { phone: '', phoneLabel: 'mobile', additionalPhones: [work, home] });
    expect(b).toMatchObject({ phone: work.value, phoneLabel: 'work' });
    expect(b.additionalPhones.map((p) => p.value)).toEqual([home.value]);
  });

  it('dedupes by digits, adopts the label of the same number unless told not to, caps at 5', () => {
    const mine = { phone: '998905551234', phoneLabel: 'mobile' as const, additionalPhones: [{ ...work, privacy: 'connections' as const }] };
    const same = mergePhones(mine, { phone: '+998 (90) 555-12-34', phoneLabel: 'home', additionalPhones: [work] });
    expect(same).toMatchObject({ changed: true, phoneLabel: 'home' });
    expect(same.additionalPhones).toHaveLength(1);
    expect(mergePhones(mine, { phone: '+998 90 555 12 34', phoneLabel: 'home', additionalPhones: [] }, { adoptLabel: false }).changed).toBe(false);

    const many = Array.from({ length: 8 }, (_, i) => ({ ...work, id: `6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8b0${i}`, value: `+1 555 000 00 0${i}` }));
    const capped = mergePhones(mine, { phone: '+998 93 000 00 00', phoneLabel: 'other', additionalPhones: many });
    expect(capped.additionalPhones).toHaveLength(5);
    expect(capped.additionalPhones[1]).toMatchObject({ value: '+998 93 000 00 00', label: 'other', privacy: 'connections' });
    expect(capped.phone).toBe('998905551234');
  });

  it('compares digits only', () => {
    expect(phoneDigits('+998 (90) 555-12-34')).toBe('998905551234');
  });
});

describe('wire', () => {
  const base = {
    id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a20',
    createdAt: '2026-09-26T10:00:00Z',
    updatedAt: '2026-09-26T10:00:00Z',
  };
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

  it('absent or null phone keys stay undefined (an older client): stored values are kept', () => {
    const old = ProfileIn.parse(profile);
    expect(old.phoneLabel).toBeUndefined();
    expect(old.additionalPhones).toBeUndefined();
    expect(ProfileIn.parse({ ...profile, phoneLabel: null, additionalPhones: null }).additionalPhones).toBeUndefined();
    const current = ProfileIn.parse({ ...profile, phoneLabel: 'work', additionalPhones: [{ ...work, id: work.id.toUpperCase() }] });
    expect(current.phoneLabel).toBe('work');
    expect(current.additionalPhones).toEqual([work]);
  });

  it('validates: at most 5 extra phones, each ≤ 40 characters, known labels', () => {
    expect(ProfileIn.safeParse({ ...profile, additionalPhones: Array(6).fill(work) }).success).toBe(false);
    expect(ProfileIn.safeParse({ ...profile, additionalPhones: [{ ...work, value: '1'.repeat(41) }] }).success).toBe(false);
    expect(ProfileIn.safeParse({ ...profile, additionalPhones: [{ ...work, label: 'fax' }] }).success).toBe(false);
    expect(ProfileIn.safeParse({ ...profile, phoneLabel: 'pager' }).success).toBe(false);
  });

  it('a connection phone may omit its privacy (→ connections)', () => {
    const connection = ConnectionIn.parse({
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
      additionalPhones: [{ id: work.id, label: 'work', value: work.value }],
    });
    expect(connection.additionalPhones).toEqual([{ ...work, privacy: 'connections' }]);
  });
});
