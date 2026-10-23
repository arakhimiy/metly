import { describe, expect, it } from 'vitest';
import { reminderMessage } from './telegram.service';

describe('reminderMessage', () => {
  it('names the person, the reason and links the Telegram chat — never the note', () => {
    expect(reminderMessage({ personName: 'Sardor', title: 'Send the deck', channel: 'telegram', telegramHandle: '@sardor_r' })).toBe(
      'Follow up with Sardor\nSend the deck\nhttps://t.me/sardor_r',
    );
    expect(reminderMessage({ personName: 'Sardor', title: 'Call back', channel: 'call', telegramHandle: '@sardor_r' })).toBe(
      'Follow up with Sardor\nCall back',
    );
    expect(reminderMessage({ personName: null, title: '  ', channel: 'telegram', telegramHandle: 'bad handle!' })).toBe('Follow up\nFollow up');
    expect(reminderMessage({ personName: 'A', title: 'x', channel: 'telegram', telegramHandle: 'https://t.me/aziza_k' })).toContain('https://t.me/aziza_k');
  });
});
