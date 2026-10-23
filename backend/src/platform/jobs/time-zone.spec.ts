import { describe, expect, it } from 'vitest';
import { endOfLocalDay, isValidTimeZone, zonedMidnight } from './time-zone';

describe('time zones', () => {
  it('finds the last millisecond of the local day', () => {
    // 15:00 in Tashkent (UTC+5, no DST).
    expect(endOfLocalDay(new Date('2026-01-10T10:00:00Z'), 'Asia/Tashkent').toISOString()).toBe('2026-01-10T18:59:59.999Z');
    // 21:00 UTC is already the next day in Tashkent.
    expect(endOfLocalDay(new Date('2026-01-10T21:00:00Z'), 'Asia/Tashkent').toISOString()).toBe('2026-01-11T18:59:59.999Z');
    expect(endOfLocalDay(new Date('2026-02-01T15:00:00Z'), 'America/New_York').toISOString()).toBe('2026-02-02T04:59:59.999Z');
    expect(endOfLocalDay(new Date('2026-06-30T12:00:00Z'), 'UTC').toISOString()).toBe('2026-06-30T23:59:59.999Z');
  });

  it('handles DST change days and month/year rollover', () => {
    // US spring forward 2026-03-08: the day ends at EDT (UTC-4).
    expect(endOfLocalDay(new Date('2026-03-08T12:00:00Z'), 'America/New_York').toISOString()).toBe('2026-03-09T03:59:59.999Z');
    // Berlin fall back 2026-10-25: the day ends at CET (UTC+1).
    expect(endOfLocalDay(new Date('2026-10-25T08:00:00Z'), 'Europe/Berlin').toISOString()).toBe('2026-10-25T22:59:59.999Z');
    expect(zonedMidnight(2026, 12, 32, 'Asia/Tashkent').toISOString()).toBe('2026-12-31T19:00:00.000Z');
  });

  it('falls back to Asia/Tashkent for unknown zones', () => {
    expect(isValidTimeZone('Asia/Tashkent')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
    expect(endOfLocalDay(new Date('2026-01-10T10:00:00Z'), 'Mars/Olympus').toISOString()).toBe('2026-01-10T18:59:59.999Z');
  });
});
