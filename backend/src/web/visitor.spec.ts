import { describe, expect, it } from 'vitest';
import { deviceFamilyFromUserAgent, iosMajorFromUserAgent, ipPrefix, isBot, platformFromUserAgent, visitorHash } from './visitor';

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36';
const DESKTOP = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

describe('isBot', () => {
  it('flags crawlers, link previews, headless browsers and empty agents', () => {
    for (const ua of [
      'Googlebot/2.1 (+http://www.google.com/bot.html)',
      'facebookexternalhit/1.1',
      'Slackbot-LinkExpanding 1.0',
      'TelegramBot (like TwitterBot)',
      'WhatsApp/2.23.20.0',
      'Mozilla/5.0 (compatible; Discordbot/2.0)',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 HeadlessChrome/120.0 Safari/537.36',
      'curl/8.4.0',
      '',
    ]) {
      expect(isBot(ua), ua).toBe(true);
    }
  });

  it('lets real browsers through', () => {
    for (const ua of [IPHONE, ANDROID, DESKTOP]) expect(isBot(ua)).toBe(false);
  });
});

describe('platform', () => {
  it('detects iOS, Android, in-app and desktop', () => {
    expect(platformFromUserAgent(IPHONE)).toBe('ios');
    expect(platformFromUserAgent(ANDROID)).toBe('android');
    expect(platformFromUserAgent(DESKTOP)).toBe('desktop');
    expect(platformFromUserAgent(`${IPHONE} Instagram 300.0`)).toBe('inapp');
    expect(platformFromUserAgent('Mozilla/5.0 (Linux; Android 14; wv) AppleWebKit/537.36 Telegram-Android/10.0')).toBe('inapp');
  });

  it('reads the iOS major version and device family', () => {
    expect(iosMajorFromUserAgent(IPHONE)).toBe(18);
    expect(iosMajorFromUserAgent('Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X)')).toBe(17);
    expect(iosMajorFromUserAgent(DESKTOP)).toBeNull();
    expect(deviceFamilyFromUserAgent(IPHONE)).toBe('iphone');
    expect(deviceFamilyFromUserAgent('Mozilla/5.0 (iPad; CPU OS 17_4 like Mac OS X)')).toBe('ipad');
    expect(deviceFamilyFromUserAgent(DESKTOP)).toBe('mac');
    expect(deviceFamilyFromUserAgent(ANDROID)).toBe('other');
  });
});

describe('ipPrefix', () => {
  it('keeps only the IPv4 /24 and IPv6 /64', () => {
    expect(ipPrefix('203.0.113.77')).toBe('203.0.113.0/24');
    expect(ipPrefix('::ffff:203.0.113.77')).toBe('203.0.113.0/24');
    expect(ipPrefix('2001:db8:85a3:8d3:1319:8a2e:370:7348')).toBe('2001:db8:85a3:8d3::/64');
    expect(ipPrefix('2001:db8::1')).toBe('2001:db8:0:0::/64');
    expect(ipPrefix('fe80::1%en0')).toBe('fe80:0:0:0::/64');
    expect(ipPrefix('::1')).toBe('0:0:0:0::/64');
    expect(ipPrefix('nonsense')).toBe('unknown');
    expect(ipPrefix(undefined)).toBe('unknown');
  });
});

describe('visitorHash', () => {
  it('is stable per (ip, ua, card), differs otherwise and never contains the IP', () => {
    const a = visitorHash('secret', '203.0.113.7', IPHONE, 'card-1');
    expect(a).toBe(visitorHash('secret', '203.0.113.7', IPHONE, 'card-1'));
    expect(a).not.toBe(visitorHash('secret', '203.0.113.8', IPHONE, 'card-1'));
    expect(a).not.toBe(visitorHash('secret', '203.0.113.7', IPHONE, 'card-2'));
    expect(a).not.toBe(visitorHash('other', '203.0.113.7', IPHONE, 'card-1'));
    expect(a).not.toContain('203');
  });
});
