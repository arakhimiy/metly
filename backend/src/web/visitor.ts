import { isIP } from 'node:net';
import { hmac } from '../common/crypto';

// Visitor heuristics for the public page: bots, platform, privacy-preserving visitor keys.

export type WebPlatform = 'ios' | 'android' | 'inapp' | 'desktop';

const BOT_UA =
  /bot\b|bot\/|crawler|crawl|spider|slurp|preview|facebookexternalhit|facebookcatalog|slackbot|telegrambot|whatsapp|discordbot|headless|phantomjs|lighthouse|pingdom|curl\/|wget\/|python-requests|python-urllib|go-http-client|okhttp|java\/|libwww|httpclient|embedly|quora link|vkshare|skypeuripreview|bingpreview|google-inspectiontool/i;

/** Link-preview fetchers, crawlers, headless browsers and scripts (and requests without a UA). */
export function isBot(userAgent: string | undefined | null): boolean {
  const ua = (userAgent ?? '').trim();
  if (ua.length < 8) return true;
  return BOT_UA.test(ua);
}

const IN_APP_UA = /FBAN|FBAV|FB_IAB|Instagram|Line\/|MicroMessenger|Telegram|Twitter|LinkedInApp|Snapchat|TikTok|musical_ly|GSA\/|; wv\)/i;

export function platformFromUserAgent(userAgent: string | undefined | null): WebPlatform {
  const ua = userAgent ?? '';
  if (IN_APP_UA.test(ua)) return 'inapp';
  if (/iPhone|iPad|iPod/.test(ua)) return 'ios';
  if (/Android/i.test(ua)) return 'android';
  return 'desktop';
}

/** Android, in-app browsers (Telegram, Instagram…) included. */
export function isAndroidUserAgent(userAgent: string | undefined | null): boolean {
  return /Android/i.test(userAgent ?? '');
}

/** iOS major version from a Safari/WebKit user agent ("iPhone OS 18_1" / "CPU OS 17_4"), else null. */
export function iosMajorFromUserAgent(userAgent: string | undefined | null): number | null {
  const match = /(?:iPhone|CPU) OS (\d+)[_.]/.exec(userAgent ?? '');
  return match ? Number(match[1]) : null;
}

/** "iphone" | "ipad" | "mac" (iPadOS asks for the desktop site by default) | "other". */
export function deviceFamilyFromUserAgent(userAgent: string | undefined | null): 'iphone' | 'ipad' | 'mac' | 'other' {
  const ua = userAgent ?? '';
  if (/iPhone|iPod/.test(ua)) return 'iphone';
  if (/iPad/.test(ua)) return 'ipad';
  if (/Macintosh/.test(ua)) return 'mac';
  return 'other';
}

/**
 * The network part of an address — IPv4 /24 (`203.0.113.0/24`), IPv6 /64 (`2001:db8:1:2::/64`).
 * Full addresses are never stored.
 */
export function ipPrefix(ip: string | undefined | null): string {
  let address = (ip ?? '').trim();
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
  if (mapped?.[1]) address = mapped[1];
  const zone = address.indexOf('%');
  if (zone >= 0) address = address.slice(0, zone);
  const version = isIP(address);
  if (version === 4) {
    const parts = address.split('.');
    return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
  }
  if (version === 6) {
    const groups = expandIpv6(address);
    return `${groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, '')).join(':')}::/64`;
  }
  return 'unknown';
}

function expandIpv6(address: string): string[] {
  let text = address.toLowerCase();
  // Embedded IPv4 tail (e.g. 64:ff9b::192.0.2.1) → two hex groups.
  const v4 = /(\d+)\.(\d+)\.(\d+)\.(\d+)$/.exec(text);
  if (v4) {
    const [a, b, c, d] = v4.slice(1).map(Number) as [number, number, number, number];
    text = text.slice(0, v4.index) + `${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }
  const [head = '', tail] = text.split('::');
  const left = head ? head.split(':') : [];
  const right = tail !== undefined && tail !== '' ? tail.split(':') : [];
  const fill = tail !== undefined ? new Array(Math.max(0, 8 - left.length - right.length)).fill('0') : [];
  return [...left, ...fill, ...right].map((g) => g.padStart(4, '0'));
}

/** Per card, per visitor key for de-duplication. Salted, so the raw IP cannot be recovered. */
export function visitorHash(secret: string, ip: string, userAgent: string, cardId: string): string {
  return hmac(secret, `visit|${cardId}|${ip}|${userAgent}`);
}
