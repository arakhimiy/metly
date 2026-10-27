import { type Lang, plural } from './lang';

// Message catalog for push notifications and the Telegram bot, in Uzbek (Latin), Russian and English.
// Terminology follows the app's glossary: card = vizitka / визитка, connection = tanish / контакт,
// follow-up = eslatma / напоминание. Russian texts never put a person's name in an oblique case or
// next to a gendered verb (names are typed in Latin or Cyrillic; neither declines reliably), so names
// stand alone or as the subject of a plural/future verb. Uzbek pronouns have no gender.
//
// Push callers name a message and its parameters (`{ id: 'followUpDue', params: {...} }`);
// PushService renders it once per language, for each device in its own `devices.locale`.

export interface PushText {
  title: string;
  body: string;
}

type Renderers<P> = Record<Lang, (params: P) => PushText>;
const define = <P>(renderers: Renderers<P>) => renderers;

function followUp(lang: Lang, personName: string | null, title: string): PushText {
  const reason = title.trim();
  switch (lang) {
    case 'uz':
      return { title: personName ? `${personName} bilan bog‘laning` : 'Eslatma', body: reason || 'Bog‘lanish vaqti keldi' };
    case 'ru':
      return { title: personName ? `Напоминание: ${personName}` : 'Напоминание', body: reason || 'Пора напомнить о себе' };
    case 'en':
      return { title: personName ? `Follow up with ${personName}` : 'Follow up', body: reason || 'Follow up' };
  }
}

export const PUSH_MESSAGES = {
  /** PUSH_CONNECT_REQUEST. `name`: the requester's first name (null when unknown). */
  connectRequest: define<{ name: string | null; eventName: string | null }>({
    uz: ({ name, eventName }) => ({
      title: `${name ?? 'Kimdir'} siz bilan vizitka almashmoqchi`,
      body: eventName ? `${eventName} tadbirida` : 'Qabul qilish yoki rad etish uchun bosing.',
    }),
    ru: ({ name, eventName }) => ({
      title: `${name ?? 'Кто-то'} хочет обменяться визитками`,
      body: eventName ? `На мероприятии «${eventName}»` : 'Нажмите, чтобы принять или отклонить.',
    }),
    en: ({ name, eventName }) => ({
      title: `${name ?? 'Someone'} wants to swap cards`,
      body: eventName ? `At ${eventName}` : 'Tap to accept or decline.',
    }),
  }),

  /** Someone opened the owner's shared card link in the app and was connected right away. */
  connectViaLink: define<{ name: string | null }>({
    uz: ({ name }) => ({ title: `${name ?? 'Kimdir'} siz bilan vizitka almashdi`, body: 'Vizitkangiz havolasi orqali.' }),
    ru: ({ name }) => ({ title: name ? `Новый контакт: ${name}` : 'Новый контакт', body: 'Обмен по ссылке на вашу визитку.' }),
    en: ({ name }) => ({ title: `${name ?? 'Someone'} connected with you`, body: 'They used the link to your card.' }),
  }),

  /** The recipient accepted the requester's connect request. */
  connectAccepted: define<{ name: string | null }>({
    uz: ({ name }) => ({
      title: name ? `Siz va ${name} vizitka almashdingiz` : 'Vizitka almashdingiz',
      body: 'Suhbat yodingizdaligida izoh qo‘shing.',
    }),
    ru: ({ name }) => ({
      title: name ? `Вы и ${name} обменялись визитками` : 'Вы обменялись визитками',
      body: 'Добавьте заметку, пока помните разговор.',
    }),
    en: ({ name }) => ({
      title: name ? `You and ${name} swapped cards` : 'You swapped cards',
      body: 'Add a note while you remember the conversation.',
    }),
  }),

  /** A web visitor sent their contact back from the card page. `context`: event name or "Met at". */
  shareBackReceived: define<{ name: string; context: string | null }>({
    uz: ({ name, context }) => ({ title: `${name} sizga kontaktini yubordi`, body: context ?? 'Veb-sahifangiz orqali' }),
    ru: ({ name, context }) => ({ title: `Ответный контакт: ${name}`, body: context ?? 'С вашей веб-страницы' }),
    en: ({ name, context }) => ({ title: `${name} shared their contact with you`, body: context ?? 'From your web page' }),
  }),

  /** PUSH_FOLLOWUP. `title`: the follow-up's own reason ("Send the deck") — never the private note. */
  followUpDue: define<{ personName: string | null; title: string }>({
    uz: ({ personName, title }) => followUp('uz', personName, title),
    ru: ({ personName, title }) => followUp('ru', personName, title),
    en: ({ personName, title }) => followUp('en', personName, title),
  }),

  /** PUSH_EVENT_SUMMARY. `people`: connections met at the event. */
  eventSummary: define<{ eventName: string; people: number }>({
    uz: ({ eventName, people }) => ({
      title: eventName.trim() ? `«${eventName.trim()}» tadbiri yakunlandi` : 'Tadbiringiz yakunlandi',
      body:
        people === 0
          ? 'Qanday o‘tganini ko‘rib chiqing va eslatmalarni rejalashtiring.'
          : `${people} ta yangi ${plural('uz', people, { one: 'tanish', other: 'tanish' })}. Hammasi yodingizdaligida izoh va eslatmalar qo‘shing.`,
    }),
    ru: ({ eventName, people }) => ({
      title: eventName.trim() ? `Мероприятие «${eventName.trim()}» завершено` : 'Мероприятие завершено',
      body:
        people === 0
          ? 'Посмотрите, как всё прошло, и запланируйте напоминания.'
          : `${people} ${plural('ru', people, { one: 'новый контакт', few: 'новых контакта', many: 'новых контактов', other: 'нового контакта' })}. Добавьте заметки и напоминания, пока всё свежо в памяти.`,
    }),
    en: ({ eventName, people }) => ({
      title: `${eventName.trim() || 'Your event'} wrapped up`,
      body:
        people === 0
          ? 'See how it went and plan your follow-ups.'
          : `You met ${people} ${plural('en', people, { one: 'person', other: 'people' })}. Add notes and follow-ups while they’re fresh.`,
    }),
  }),
};

export type PushMessageId = keyof typeof PUSH_MESSAGES;
export type PushParams<K extends PushMessageId> = Parameters<(typeof PUSH_MESSAGES)[K]['en']>[0];
/** A catalog message with its parameters, e.g. `{ id: 'connectAccepted', params: { name: 'Aziza' } }`. */
export type PushTextRef = { [K in PushMessageId]: { id: K; params: PushParams<K> } }[PushMessageId];

export function renderPush(ref: PushTextRef, lang: Lang): PushText {
  const render = PUSH_MESSAGES[ref.id][lang] as (params: PushTextRef['params']) => PushText;
  return render(ref.params);
}

// ───────────────────────────── Telegram bot ─────────────────────────────

export interface TelegramText {
  /** `/start` without a link token. */
  startHelp: string;
  linked: string;
  linkExpired: string;
  /** `/stop`. */
  stopped: string;
}

export const TELEGRAM_TEXT: Record<Lang, TelegramText> = {
  uz: {
    startHelp:
      'Eslatmalarni shu yerda olish uchun Tanishly → Profil → Sozlamalar → Bildirishnomalar bo‘limini oching va «Telegram’ni ulash» tugmasini bosing.',
    linked: 'Ulandi. Tanishly eslatmalaringizni shu yerga yuboradi.',
    linkExpired: 'Bu havolaning muddati tugagan. Tanishly → Sozlamalar → Bildirishnomalar bo‘limini oching va Telegram’ni qayta ulang.',
    stopped: 'Telegram uzildi. Eslatmalar endi Tanishly ilovasidan bildirishnoma bo‘lib keladi.',
  },
  ru: {
    startHelp: 'Чтобы получать напоминания здесь, откройте Tanishly → Профиль → Настройки → Уведомления и нажмите «Подключить Telegram».',
    linked: 'Готово! Tanishly будет присылать напоминания сюда.',
    linkExpired: 'Срок действия ссылки истёк. Откройте Tanishly → Настройки → Уведомления и подключите Telegram снова.',
    stopped: 'Telegram отключён. Напоминания будут приходить уведомлениями из приложения Tanishly.',
  },
  en: {
    startHelp: 'Open Tanishly → Profile → Settings → Notifications and tap “Connect Telegram” to get reminders here.',
    linked: 'You’re connected. Tanishly will send your follow-up reminders here.',
    linkExpired: 'This link has expired. Open Tanishly → Settings → Notifications and connect Telegram again.',
    stopped: 'Disconnected. Reminders will arrive as notifications from the Tanishly app.',
  },
};

// ───────────────────────────── Synced record text ─────────────────────────────

/**
 * Placeholder job title and company of a connection created by a web share-back (the visitor only
 * types a name and a phone/Telegram). Stored once, in the owner's language at that moment.
 */
export const SHAREBACK_CONNECTION_TEXT: Record<Lang, { jobTitle: string; company: string }> = {
  uz: { jobTitle: 'Kontakt', company: 'Veb-sahifangiz orqali yuborilgan' },
  ru: { jobTitle: 'Контакт', company: 'Отправлено с вашей веб-страницы' },
  en: { jobTitle: 'Contact', company: 'Shared from your web page' },
};
