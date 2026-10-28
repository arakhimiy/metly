import { describe, expect, it } from 'vitest';
import { storedPhoneLabel, storedPhones } from './phones';
import { ConnectionIn, type LabeledPhone, ProfileIn } from './wire';

const work: LabeledPhone = { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a11', label: 'work', value: '+998 71 200 00 00', privacy: 'public' };
const home: LabeledPhone = { id: '6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a12', label: 'home', value: '+998 71 300 00 00', privacy: 'connections' };

describe('stored phones', () => {
  it('reads defensively: bad entries dropped, unknown labels → mobile', () => {
    expect(storedPhones([work, { label: 'work' }, 42, { ...home, privacy: 'nope' }])).toEqual([work, { ...home, privacy: 'connections' }]);
    expect(storedPhones(null)).toEqual([]);
    expect(storedPhoneLabel('home')).toBe('home');
    expect(storedPhoneLabel('fax')).toBe('mobile');
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
