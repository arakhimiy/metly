import { describe, expect, it } from 'vitest';
import { reminderMessage } from './telegram.service';

describe('reminderMessage', () => {
  it('names the person, the reason and links the Telegram chat — never the note', () => {
    expect(reminderMessage({ personName: 'Sardor', title: 'Send the deck', channel: 'telegram', telegramHandle: '@sardor_r' }, 'en')).toBe(
      'Follow up with Sardor\nSend the deck\nhttps://t.me/sardor_r',
    );
    expect(reminderMessage({ personName: 'Sardor', title: 'Call back', channel: 'call', telegramHandle: '@sardor_r' }, 'en')).toBe(
      'Follow up with Sardor\nCall back',
    );
    expect(reminderMessage({ personName: null, title: '  ', channel: 'telegram', telegramHandle: 'bad handle!' }, 'en')).toBe('Follow up\nFollow up');
    expect(reminderMessage({ personName: 'A', title: 'x', channel: 'telegram', telegramHandle: 'https://t.me/aziza_k' }, 'en')).toContain('https://t.me/aziza_k');
  });

  it('speaks the user’s language', () => {
    const reminder = { personName: 'Sardor', title: 'Taqdimotni yuborish', channel: 'telegram', telegramHandle: '@sardor_r' };
    expect(reminderMessage(reminder, 'uz')).toBe('Sardor bilan bog‘laning\nTaqdimotni yuborish\nhttps://t.me/sardor_r');
    expect(reminderMessage({ ...reminder, title: 'Отправить презентацию' }, 'ru')).toBe('Напоминание: Sardor\nОтправить презентацию\nhttps://t.me/sardor_r');
    expect(reminderMessage({ personName: null, title: '', channel: 'email' }, 'uz')).toBe('Eslatma\nBog‘lanish vaqti keldi');
    expect(reminderMessage({ personName: null, title: '', channel: 'email' }, 'ru')).toBe('Напоминание\nПора напомнить о себе');
  });
});
