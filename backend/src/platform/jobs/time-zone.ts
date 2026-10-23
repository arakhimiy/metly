/** Owners without a registered device are assumed to be in Uzbekistan (the launch market). */
export const DEFAULT_TIME_ZONE = 'Asia/Tashkent';

export function isValidTimeZone(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone });
    return true;
  } catch {
    return false;
  }
}

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(timeZone: string): Intl.DateTimeFormat {
  let f = formatters.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
    });
    formatters.set(timeZone, f);
  }
  return f;
}

/** Wall-clock fields of `instant` in `timeZone`. */
export function localParts(instant: Date, timeZone: string) {
  const parts = formatter(timeZone).formatToParts(instant);
  const get = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  return { year: get('year'), month: get('month'), day: get('day'), hour: get('hour'), minute: get('minute'), second: get('second') };
}

/** UTC offset of `timeZone` at `instant`, in ms (Asia/Tashkent → +5 h). */
function offsetMs(instant: Date, timeZone: string): number {
  const p = localParts(instant, timeZone);
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return asUtc - (instant.getTime() - instant.getUTCMilliseconds());
}

/** The instant of local midnight starting `year-month-day` in `timeZone` (day may overflow). */
export function zonedMidnight(year: number, month: number, day: number, timeZone: string): Date {
  const wall = Date.UTC(year, month - 1, day);
  let t = wall - offsetMs(new Date(wall), timeZone);
  // Second pass settles DST transitions between the guess and the answer.
  t = wall - offsetMs(new Date(t), timeZone);
  return new Date(t);
}

/** Last millisecond of the local calendar day that contains `instant`. */
export function endOfLocalDay(instant: Date, timeZone: string): Date {
  const zone = isValidTimeZone(timeZone) ? timeZone : DEFAULT_TIME_ZONE;
  const { year, month, day } = localParts(instant, zone);
  return new Date(zonedMidnight(year, month, day + 1, zone).getTime() - 1);
}
