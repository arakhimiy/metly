import { Inject, Injectable, Logger } from '@nestjs/common';
import { ApiError } from '../../common/api-error';
import { randomToken, sha256 } from '../../common/crypto';
import { iso, minutes } from '../../common/time';
import { ENV, type Env } from '../../config/env';
import type { Prisma } from '../../generated/prisma/client';
import { DEFAULT_LANG, type Lang, langFromLocale } from '../../i18n/lang';
import { renderPush, TELEGRAM_TEXT } from '../../i18n/messages';
import { PrismaService, type Tx } from '../../prisma/prisma.service';
import { RecordsService, type WriteContext } from '../../records/records.service';

const LINK_TTL_MS = minutes(15);
const BOT_API_TIMEOUT_MS = 10_000;

export interface TelegramUpdate {
  update_id?: number;
  message?: {
    text?: string;
    chat?: { id?: number | string; type?: string };
    /** The Telegram user's app language (IETF tag), a hint for chats not bound to an account yet. */
    from?: { language_code?: string };
  };
}

export interface SendResult {
  ok: boolean;
  /** The user blocked the bot or deleted the chat: the link is dead. */
  blocked?: boolean;
}

export interface ReminderText {
  personName: string | null;
  title: string;
  channel: string;
  /** The person's Telegram handle, for a one-tap link to the chat. */
  telegramHandle?: string | null;
}

/**
 * "Follow up with Sardor Rashidov\nSend the deck\nhttps://t.me/sardor" (never note text) — the same
 * title and body as the reminder push, in `lang`.
 */
export function reminderMessage(r: ReminderText, lang: Lang): string {
  const text = renderPush({ id: 'followUpDue', params: { personName: r.personName, title: r.title } }, lang);
  const lines = [text.title, text.body];
  const handle = r.telegramHandle?.trim().replace(/^@/, '').replace(/^https?:\/\/t\.me\//i, '');
  if (r.channel === 'telegram' && handle && /^[A-Za-z0-9_]{4,32}$/.test(handle)) lines.push(`https://t.me/${handle}`);
  return lines.join('\n');
}

/**
 * Reminder delivery through @TanishlyBot: one-time deep links, the bot webhook that binds a chat to
 * a user, and `sendMessage` for reminders. `users.telegram_chat_id` is the source of truth;
 * `notificationPrefs.telegramLinked` on the profile mirrors it (server-owned, synced with a seq bump).
 */
@Injectable()
export class TelegramService {
  private readonly logger = new Logger(TelegramService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly records: RecordsService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  get isConfigured(): boolean {
    return Boolean(this.env.TELEGRAM_BOT_TOKEN);
  }

  /** POST /v1/integrations/telegram/link: `https://t.me/<bot>?start=<token>`, valid 15 minutes. */
  async createLink(userId: string, now = new Date()) {
    if (!this.isConfigured) throw ApiError.unavailable('Telegram reminders are not available right now.');
    const token = randomToken(24);
    const expiresAt = new Date(now.getTime() + LINK_TTL_MS);
    await this.prisma.write(async (tx) => {
      // Only the newest link works; older ones (and expired ones) go.
      await tx.telegramLinkToken.deleteMany({ where: { userId } });
      await tx.telegramLinkToken.create({ data: { tokenHash: sha256(token), userId, expiresAt } });
    });
    return { botUrl: `https://t.me/${this.env.TELEGRAM_BOT_USERNAME}?start=${token}`, expiresAt: iso(expiresAt) };
  }

  /** DELETE /v1/integrations/telegram/link — reminders fall back to push. */
  async unlink(userId: string) {
    await this.records.write(userId, async (ctx) => {
      await ctx.tx.user.update({ where: { id: userId }, data: { telegramChatId: null } });
      await ctx.tx.telegramLinkToken.deleteMany({ where: { userId } });
      // A user action, like toggling it in Settings: it carries a fresh updatedAt (mock behaviour).
      await this.mirrorLinked(ctx, userId, false, { touch: true });
    });
  }

  /** Bot webhook. Never throws for bad input: Telegram retries anything but 2xx. */
  async handleUpdate(update: TelegramUpdate): Promise<void> {
    const message = update.message;
    const chatId = message?.chat?.id;
    const text = message?.text?.trim() ?? '';
    if (chatId === undefined || chatId === null || message?.chat?.type !== 'private') return;
    const chat = String(chatId);
    const hint = message.from?.language_code;

    const start = /^\/start(?:@\w+)?(?:\s+(\S+))?$/.exec(text);
    if (start) {
      const token = start[1];
      if (!token) {
        await this.sendMessage(chat, TELEGRAM_TEXT[await this.chatLang(chat, hint)].startHelp);
        return;
      }
      const linked = await this.bind(chat, token);
      const copy = TELEGRAM_TEXT[await this.chatLang(chat, hint)];
      await this.sendMessage(chat, linked ? copy.linked : copy.linkExpired);
      return;
    }
    if (/^\/stop(?:@\w+)?$/.test(text)) {
      // The language is read while the chat still belongs to the account.
      const copy = TELEGRAM_TEXT[await this.chatLang(chat, hint)];
      const user = await this.prisma.user.findUnique({ where: { telegramChatId: chat }, select: { id: true } });
      if (user) await this.unlinkByChat(chat);
      await this.sendMessage(chat, copy.stopped);
    }
  }

  /**
   * The language for a chat: the bound user's most recent device locale; for a chat not bound to an
   * account (or an account without devices) Telegram's `language_code`, then Uzbek.
   */
  async chatLang(chatId: string, hint?: string): Promise<Lang> {
    const device = await this.prisma.device.findFirst({
      where: { user: { telegramChatId: chatId } },
      orderBy: { updatedAt: 'desc' },
      select: { locale: true },
    });
    if (device) return langFromLocale(device.locale);
    return hint?.trim() ? langFromLocale(hint) : DEFAULT_LANG;
  }

  /** Binds the chat to the token's user. A chat belongs to one account: it moves off any other. */
  async bind(chatId: string, token: string, now = new Date()): Promise<boolean> {
    const link = await this.prisma.telegramLinkToken.findUnique({ where: { tokenHash: sha256(token) } });
    if (!link || link.expiresAt <= now) return false;
    const userId = link.userId;
    const previous = await this.prisma.user.findUnique({ where: { telegramChatId: chatId }, select: { id: true } });
    let bound = false;
    await this.records.write(userId, async (ctx) => {
      const { tx } = ctx;
      await this.prisma.lockUsers(tx, previous && previous.id !== userId ? [userId, previous.id] : [userId]);
      const consumed = await tx.telegramLinkToken.deleteMany({ where: { tokenHash: link.tokenHash, expiresAt: { gt: now } } });
      if (consumed.count !== 1) return;
      const holder = await tx.user.findUnique({ where: { telegramChatId: chatId }, select: { id: true } });
      if (holder && holder.id !== userId) {
        await tx.user.update({ where: { id: holder.id }, data: { telegramChatId: null } });
        await this.mirrorLinked(ctx, holder.id, false, { touch: false });
      }
      const user = await tx.user.findUnique({ where: { id: userId }, select: { telegramChatId: true } });
      if (!user) return;
      await tx.user.update({ where: { id: userId }, data: { telegramChatId: chatId } });
      await this.mirrorLinked(ctx, userId, true, { touch: false });
      bound = true;
    });
    return bound;
  }

  /** The chat is gone (bot blocked, /stop): forget it and fall back to push. */
  async unlinkByChat(chatId: string): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { telegramChatId: chatId }, select: { id: true } });
    if (!user) return;
    await this.records.write(user.id, async (ctx) => {
      const cleared = await ctx.tx.user.updateMany({ where: { id: user.id, telegramChatId: chatId }, data: { telegramChatId: null } });
      if (cleared.count === 1) await this.mirrorLinked(ctx, user.id, false, { touch: false });
    });
  }

  /**
   * Mirrors the link state into the profile's notificationPrefs (`telegramLinked`, and `delivery`
   * back to `push` when unlinked) with a seq bump so devices pull it. Without a profile there is
   * nothing to mirror: upsertProfile derives telegramLinked from users.telegram_chat_id later.
   */
  private async mirrorLinked(ctx: WriteContext, userId: string, linked: boolean, opts: { touch: boolean }) {
    const tx: Tx = ctx.tx;
    ctx.effects.usersChanged.add(userId);
    const profile = await tx.profile.findUnique({ where: { userId } });
    if (!profile || profile.deletedAt) {
      await this.prisma.nextSeq(tx, userId);
      return;
    }
    const prefs: Record<string, unknown> = { ...(profile.notificationPrefs as Record<string, unknown>), telegramLinked: linked };
    if (!linked && prefs.delivery === 'telegramBot') prefs.delivery = 'push';
    const now = new Date();
    const row = await tx.profile.update({
      where: { userId },
      data: {
        notificationPrefs: prefs as Prisma.InputJsonValue,
        seq: await this.prisma.nextSeq(tx, userId),
        ...(opts.touch ? { updatedAt: profile.updatedAt > now ? profile.updatedAt : now } : {}),
      },
    });
    if (userId === ctx.userId) this.records.emitProfile(ctx, row);
  }

  /** Bot API `sendMessage` (plain text). Failures are logged, never thrown. */
  async sendMessage(chatId: string, text: string): Promise<SendResult> {
    const token = this.env.TELEGRAM_BOT_TOKEN;
    if (!token) return { ok: false };
    try {
      const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
        signal: AbortSignal.timeout(BOT_API_TIMEOUT_MS),
      });
      if (res.ok) return { ok: true };
      const body = (await res.json().catch(() => ({}))) as { description?: string };
      // 403: "bot was blocked by the user" / "user is deactivated"; 400 "chat not found".
      const blocked = res.status === 403 || (res.status === 400 && /chat not found/i.test(body.description ?? ''));
      this.logger.warn({ status: res.status, description: body.description }, 'Telegram sendMessage failed');
      return { ok: false, blocked };
    } catch (error) {
      this.logger.warn({ err: error }, 'Telegram sendMessage failed');
      return { ok: false };
    }
  }

  /**
   * Sends a follow-up reminder to the user's chat, in the language of their most recent device; a dead
   * chat is unlinked (prefs fall back to push).
   */
  async sendReminder(chatId: string, reminder: ReminderText): Promise<boolean> {
    const result = await this.sendMessage(chatId, reminderMessage(reminder, await this.chatLang(chatId)));
    if (result.blocked) await this.unlinkByChat(chatId);
    return result.ok;
  }
}
