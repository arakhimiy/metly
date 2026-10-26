import { randomBytes, randomUUID } from 'node:crypto';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { RemindersJob } from '../src/platform/jobs/reminders.job';
import { PrismaService } from '../src/prisma/prisma.service';
import { pushTestSink } from '../src/push/push-test-sink';
import { expectSchema } from './contract';
import { connection, createApp, followUp, notificationPrefs, now, profile, request, resetRateLimits, type Session, signIn } from './helpers';

const BOT_TOKEN = '123456:test-bot-token';
const SECRET = 'telegram-webhook-secret';

/** Bot API calls the server made (global fetch is stubbed; nothing leaves the process). */
interface BotCall {
  method: string;
  body: { chat_id: string; text: string };
}

describe('platform: telegram reminders', () => {
  let app: NestExpressApplication;
  let prisma: PrismaService;
  const saved = { ...process.env };
  const calls: BotCall[] = [];
  let botStatus = 200;

  beforeAll(async () => {
    // env is read by createApp() → loadEnv().
    process.env.TELEGRAM_BOT_TOKEN = BOT_TOKEN;
    process.env.TELEGRAM_WEBHOOK_SECRET = SECRET;
    process.env.TELEGRAM_BOT_USERNAME = 'TanishlyBot';
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string | URL, init?: RequestInit) => {
        const match = /^https:\/\/api\.telegram\.org\/bot([^/]+)\/(\w+)$/.exec(String(url));
        if (!match || match[1] !== BOT_TOKEN) throw new Error(`unexpected fetch ${String(url)}`);
        calls.push({ method: match[2]!, body: JSON.parse(String(init?.body)) as BotCall['body'] });
        const ok = botStatus === 200;
        return new Response(JSON.stringify(ok ? { ok: true, result: {} } : { ok: false, error_code: botStatus, description: 'Forbidden: bot was blocked by the user' }), {
          status: botStatus,
          headers: { 'content-type': 'application/json' },
        });
      }),
    );
    app = await createApp();
    prisma = app.get(PrismaService);
  });
  afterAll(async () => {
    await app.close();
    vi.unstubAllGlobals();
    process.env = saved;
  });
  beforeEach(() => {
    resetRateLimits(app);
    pushTestSink.clear();
    calls.length = 0;
    botStatus = 200;
  });

  const http = () => request(app.getHttpServer());
  const webhook = (body: object, secret: string | null = SECRET) => {
    const r = http().post('/v1/integrations/telegram/webhook');
    if (secret !== null) r.set('X-Telegram-Bot-Api-Secret-Token', secret);
    return r.send(body);
  };
  const start = (chatId: number, token?: string) =>
    webhook({ update_id: Date.now(), message: { message_id: 1, chat: { id: chatId, type: 'private' }, text: token ? `/start ${token}` : '/start' } });
  const pull = (s: Session, since?: string) =>
    http()
      .get('/v1/sync')
      .query(since ? { since } : {})
      .set(s.auth)
      .expect(200);
  const withProfile = async (prefs: Record<string, unknown> = {}) => {
    const s = await signIn(app);
    await http()
      .put('/v1/me/profile')
      .set(s.auth)
      .send(profile({ notificationPrefs: { ...notificationPrefs, ...prefs } }))
      .expect(200);
    return s;
  };
  const linkToken = async (s: Session) => {
    const res = await http().post('/v1/integrations/telegram/link').set(s.auth).set('Idempotency-Key', randomUUID()).expect(200);
    expectSchema('TelegramLink', res.body);
    const url = new URL(res.body.botUrl as string);
    expect(url.origin + url.pathname).toBe('https://t.me/TanishlyBot');
    expect(Date.parse(res.body.expiresAt) - Date.now()).toBeGreaterThan(14 * 60_000);
    return url.searchParams.get('start')!;
  };

  it('links a chat through /start, mirrors telegramLinked into the profile and syncs it', async () => {
    const s = await withProfile();
    const cursor = (await pull(s)).body.cursor as string;
    const token = await linkToken(s);
    expect(token).toMatch(/^[A-Za-z0-9_-]{32}$/);
    // Only the hash is stored.
    expect(await prisma.telegramLinkToken.count({ where: { tokenHash: token } })).toBe(0);

    const chatId = 700_000_000 + Math.floor(Math.random() * 1000);
    await start(chatId, token).expect(200);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: s.userId } })).telegramChatId).toBe(String(chatId));
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatchObject({ method: 'sendMessage', body: { chat_id: String(chatId), text: expect.stringContaining('connected') } });

    const delta = await pull(s, cursor);
    expect(delta.body.changes.profile.notificationPrefs.telegramLinked).toBe(true);
    // Single use.
    calls.length = 0;
    await start(chatId, token).expect(200);
    expect(calls[0]!.body.text).toContain('expired');

    // A later profile write from a device cannot clear the server-owned flag.
    const me = await http().get('/v1/me/profile').set(s.auth).expect(200);
    const rewritten = await http()
      .put('/v1/me/profile')
      .set(s.auth)
      .send({ ...me.body, notificationPrefs: { ...me.body.notificationPrefs, telegramLinked: false, delivery: 'telegramBot' }, updatedAt: now(5000) })
      .expect(200);
    expect(rewritten.body.notificationPrefs).toMatchObject({ telegramLinked: true, delivery: 'telegramBot' });
  });

  it('rejects webhook calls without the secret', async () => {
    await webhook({ update_id: 1 }, null).expect(401);
    await webhook({ update_id: 1 }, 'wrong').expect(401);
    await webhook({ update_id: 1 }).expect(200);
    await start(42).expect(200);
    expect(calls[0]!.body.text).toContain('Connect Telegram');
  });

  it('moves a chat to the account that linked it last', async () => {
    const a = await withProfile();
    const b = await withProfile();
    const chatId = 710_000_000 + Math.floor(Math.random() * 1000);
    await start(chatId, await linkToken(a)).expect(200);
    await start(chatId, await linkToken(b)).expect(200);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).telegramChatId).toBeNull();
    expect((await prisma.user.findUniqueOrThrow({ where: { id: b.userId } })).telegramChatId).toBe(String(chatId));
    expect((await pull(a)).body.changes.profile.notificationPrefs.telegramLinked).toBe(false);
  });

  it('delivers reminders to the bot when delivery is telegramBot', async () => {
    const s = await withProfile({ delivery: 'telegramBot' });
    await http()
      .put('/v1/me/devices/phone')
      .set(s.auth)
      .send({
        deviceId: 'phone',
        apnsToken: randomBytes(32).toString('hex'),
        apnsEnvironment: 'production',
        platform: 'ios',
        appVersion: '1',
        osVersion: '26',
        locale: 'en',
        timeZone: 'Asia/Tashkent',
      })
      .expect(204);
    const chatId = 720_000_000 + Math.floor(Math.random() * 1000);
    await start(chatId, await linkToken(s)).expect(200);
    calls.length = 0;

    const person = connection({ fullName: 'Sardor Rashidov', telegram: '@sardor_r', note: 'secret note' });
    const due = followUp({ connectionId: person.id, title: 'Send the deck', channel: 'telegram', dueAt: now(-1000) });
    await http().post('/v1/sync/push').set(s.auth).send({ changes: { connections: [person], followUps: [due] } }).expect(200);
    await app.get(RemindersJob).runOnce();

    expect(calls).toHaveLength(1);
    expect(calls[0]!.body).toEqual({
      chat_id: String(chatId),
      text: 'Follow up with Sardor Rashidov\nSend the deck\nhttps://t.me/sardor_r',
      disable_web_page_preview: true,
    });
    expect(calls[0]!.body.text).not.toContain('secret note');
    expect(pushTestSink.forUser(s.userId)).toEqual([]);
  });

  it('unlinks a chat that blocked the bot and falls back to push', async () => {
    const s = await withProfile({ delivery: 'telegramBot' });
    await http()
      .put('/v1/me/devices/phone')
      .set(s.auth)
      .send({
        deviceId: 'phone',
        apnsToken: randomBytes(32).toString('hex'),
        apnsEnvironment: 'production',
        platform: 'ios',
        appVersion: '1',
        osVersion: '26',
        locale: 'en',
        timeZone: 'Asia/Tashkent',
      })
      .expect(204);
    await start(730_000_000 + Math.floor(Math.random() * 1000), await linkToken(s)).expect(200);
    botStatus = 403;
    await http()
      .post('/v1/sync/push')
      .set(s.auth)
      .send({ changes: { followUps: [followUp({ dueAt: now(-1000) })] } })
      .expect(200);
    await app.get(RemindersJob).runOnce();
    expect((await prisma.user.findUniqueOrThrow({ where: { id: s.userId } })).telegramChatId).toBeNull();
    expect(pushTestSink.forUser(s.userId)).toHaveLength(1);
    const prefs = (await pull(s)).body.changes.profile.notificationPrefs;
    expect(prefs).toMatchObject({ telegramLinked: false, delivery: 'push' });
  });

  it('DELETE unlinks: chat cleared, telegramLinked false, delivery back to push', async () => {
    const s = await withProfile({ delivery: 'telegramBot' });
    await start(740_000_000 + Math.floor(Math.random() * 1000), await linkToken(s)).expect(200);
    const cursor = (await pull(s)).body.cursor as string;
    await http().delete('/v1/integrations/telegram/link').set(s.auth).expect(204);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: s.userId } })).telegramChatId).toBeNull();
    const delta = await pull(s, cursor);
    expect(delta.body.changes.profile.notificationPrefs).toMatchObject({ telegramLinked: false, delivery: 'push' });
  });
});
