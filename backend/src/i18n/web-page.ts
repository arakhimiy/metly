import type { ContactKind, PhoneLabel } from '../records/wire';
import type { Lang } from './lang';

// Texts of the public card page (WEB_CARD, WEB_SHAREBACK_SHEET, WEB_CONFIRMATION) and WEB_UNAVAILABLE.
// `first` is the card owner's first name as typed (Latin or Cyrillic), or "the card owner" when the
// card has none. Russian texts keep it in the nominative (no "с Камолой" / "контакт Камолы": names do
// not decline reliably); Uzbek texts attach no suffix to it ("Kamola kontaktini", "Kamola bilan"),
// except the dative "-ga" of "who receives it", which `uzDative` spells after the name's last letter.

/** Uzbek dative: "Kamola" → "Kamolaga", "Malik" → "Malikka", "Tohir Oq" → "Tohir Oqqa", "Камола" → "Камолага". */
export function uzDative(name: string): string {
  const last = name.trim().slice(-1);
  const suffix: Record<string, string> = { k: 'ka', K: 'ka', q: 'qa', Q: 'qa', к: 'ка', К: 'ка', қ: 'қа', Қ: 'қа' };
  return name.trim() + (suffix[last] ?? (/[\u0400-\u04FF]/.test(last) ? 'га' : 'ga'));
}

/** Texts the page script shows (toasts, form hints). Sent to the browser as JSON in `data-t`. */
export interface CardScriptText {
  linkCopied: string;
  openInBrowser: string;
  needName: string;
  needContact: string;
  invalidName: string;
  invalidPhone: string;
  invalidTelegram: string;
  invalidMetAt: string;
  sending: string;
  tooMany: string;
  failed: string;
  offline: string;
  removed: string;
  cannotRemove: string;
  removeFailed: string;
}

export interface CardPageText {
  /** `og:locale`. */
  ogLocale: string;
  /** `<meta name="description">` when the card shows no job title or company. */
  description: string;
  inAppNotice: string;
  copyLink: string;
  contactDetails: string;
  /** Lowercase field labels, like the app's card. */
  fieldLabel: Record<ContactKind, string>;
  /** Lowercase phone labels, used once a card shows more than one phone or a non-mobile one. */
  phoneLabel: Record<PhoneLabel, string>;
  copy: string;
  copyAria: (label: string) => string;
  phoneCopied: string;
  emailCopied: string;
  saveToContacts: string;
  exchange: (first: string) => string;
  sent: (first: string) => string;
  removeMine: string;
  ctaTitle: string;
  ctaSubtitle: string;
  ctaButton: string;
  /** Android visitors instead of the App Store button: with the Telegram waitlist, and without it. */
  androidWaitlist: string;
  androidOnly: string;
  notifyMe: string;
  /** `first` when the card shows no first name. */
  cardOwner: string;
  foot: string;
  sheetTitle: (first: string) => string;
  sheetSubtitle: (first: string) => string;
  name: string;
  namePlaceholder: string;
  phone: string;
  telegram: string;
  telegramPlaceholder: string;
  metAt: string;
  metAtPlaceholder: string;
  phoneOrTelegram: string;
  /** Above the send button: who receives the contact. */
  sendsTo: (first: string) => string;
  send: string;
  skip: string;
  doneTitle: (first: string) => string;
  doneSave: (first: string) => string;
  doneSaved: (first: string) => string;
  doneBack: (first: string) => string;
  changedMind: string;
  script: CardScriptText;
}

export const CARD_PAGE_TEXT: Record<Lang, CardPageText> = {
  uz: {
    ogLocale: 'uz_UZ',
    description: 'Tanishly’dagi raqamli vizitka',
    inAppNotice: 'Kontaktni saqlash uchun sahifani brauzerda oching.',
    copyLink: 'Havolani nusxalash',
    contactDetails: 'Kontakt ma’lumotlari',
    fieldLabel: {
      phone: 'telefon',
      whatsapp: 'whatsapp',
      telegram: 'telegram',
      instagram: 'instagram',
      email: 'email',
      website: 'veb-sayt',
      linkedin: 'linkedin',
      address: 'manzil',
    },
    phoneLabel: { mobile: 'mobil', work: 'ish telefoni', home: 'uy telefoni', other: 'boshqa telefon' },
    copy: 'Nusxalash',
    copyAria: (label) => `Nusxalash: ${label}`,
    phoneCopied: 'Telefon nusxalandi',
    emailCopied: 'Email nusxalandi',
    saveToContacts: 'Kontaktlarga saqlash',
    exchange: (first) => `${first} bilan kontakt almashish`,
    sent: (first) => `Kontaktingiz ${uzDative(first)} yuborildi.`,
    removeMine: 'Kontaktimni o‘chirish',
    ctaTitle: 'Sizga ham shunday karta kerakmi?',
    ctaSubtitle: 'Tanishly bilan 1 daqiqada yarating. Tanishganlaringiz hech qachon yo‘qolmaydi.',
    ctaButton: 'Bepul yaratish',
    androidWaitlist: 'Hozircha faqat iPhone uchun. Android chiqqanda xabar beramiz.',
    androidOnly: 'Hozircha faqat iPhone uchun.',
    notifyMe: 'Xabar olish',
    cardOwner: 'karta egasi',
    foot: 'Tanishly’da yaratilgan · Faqat ochiq ma’lumotlar ko‘rsatiladi',
    sheetTitle: (first) => `${first} bilan kontakt almashish`,
    sheetSubtitle: (first) => `Kontaktingizni yuboring va ${first} kontaktini saqlang — bir qadamda.`,
    name: 'Ism',
    namePlaceholder: 'Ismingiz',
    phone: 'Telefon',
    telegram: 'Telegram',
    telegramPlaceholder: '@username',
    metAt: 'Qayerda tanishdik',
    metAtPlaceholder: 'Qayerda tanishdik? Ixtiyoriy',
    phoneOrTelegram: 'Telefon yoki Telegram’dan kamida bittasini kiriting.',
    sendsTo: (first) => `Kontaktingiz ${uzDative(first)} yuboriladi. Faqat u ko‘radi.`,
    send: 'Kontaktimni yuborish',
    skip: 'O‘tkazib yuborish',
    doneTitle: (first) => `Kontaktingiz ${uzDative(first)} yuborildi`,
    doneSave: (first) => `${first} kontaktini saqlash`,
    doneSaved: (first) => `${first} kontakti saqlandi`,
    doneBack: (first) => `${first} vizitkasiga qaytish`,
    changedMind: 'Fikringiz o‘zgardimi?',
    script: {
      linkCopied: 'Havola nusxalandi',
      openInBrowser: 'Saqlash uchun brauzerda oching',
      needName: 'Yuborish uchun ismingizni kiriting.',
      needContact: 'Yuborish uchun telefon yoki Telegram kiriting.',
      invalidName: 'Ismni tekshiring.',
      invalidPhone: 'Telefon raqamini tekshiring.',
      invalidTelegram: 'Telegram username’ini tekshiring: 5–32 ta harf, raqam yoki _.',
      invalidMetAt: 'Tanishgan joyni qisqaroq yozing.',
      sending: 'Yuborilmoqda…',
      tooMany: 'Urinishlar juda ko‘p. Keyinroq qayta urinib ko‘ring.',
      failed: 'Nimadir xato ketdi. Qayta urinib ko‘ring.',
      offline: 'Internet aloqasi yo‘qqa o‘xshaydi. Qayta urinib ko‘ring.',
      removed: 'Kontaktingiz o‘chirildi',
      cannotRemove: 'Bu kontaktni endi bu yerda o‘chirib bo‘lmaydi',
      removeFailed: 'Kontaktni o‘chirib bo‘lmadi. Qayta urinib ko‘ring.',
    },
  },
  ru: {
    ogLocale: 'ru_RU',
    description: 'Цифровая визитка в Tanishly',
    inAppNotice: 'Чтобы сохранить контакт, откройте страницу в браузере.',
    copyLink: 'Скопировать ссылку',
    contactDetails: 'Контактные данные',
    fieldLabel: {
      phone: 'телефон',
      whatsapp: 'whatsapp',
      telegram: 'telegram',
      instagram: 'instagram',
      email: 'email',
      website: 'сайт',
      linkedin: 'linkedin',
      address: 'адрес',
    },
    phoneLabel: { mobile: 'мобильный', work: 'рабочий телефон', home: 'домашний телефон', other: 'другой телефон' },
    copy: 'Копировать',
    copyAria: (label) => `Скопировать: ${label}`,
    phoneCopied: 'Телефон скопирован',
    emailCopied: 'Email скопирован',
    saveToContacts: 'Сохранить в контакты',
    exchange: () => 'Обменяться контактами',
    sent: () => 'Ваш контакт отправлен.',
    removeMine: 'Удалить мой контакт',
    ctaTitle: 'Хотите такую же визитку?',
    ctaSubtitle: 'Создайте её в Tanishly за 1 минуту. Ваши знакомства больше не потеряются.',
    ctaButton: 'Создать бесплатно',
    androidWaitlist: 'Пока только для iPhone. Сообщим, когда выйдет версия для Android.',
    androidOnly: 'Пока только для iPhone.',
    notifyMe: 'Сообщить мне',
    cardOwner: 'владелец визитки',
    foot: 'Сделано в Tanishly · Показаны только открытые данные',
    sheetTitle: () => 'Обмен контактами',
    sheetSubtitle: (first) => `${first} получит ваш контакт, а вы сохраните визитку — в один шаг.`,
    name: 'Имя',
    namePlaceholder: 'Ваше имя',
    phone: 'Телефон',
    telegram: 'Telegram',
    telegramPlaceholder: '@username',
    metAt: 'Где познакомились',
    metAtPlaceholder: 'Где мы познакомились? Необязательно',
    phoneOrTelegram: 'Укажите телефон или Telegram — хотя бы что-то одно.',
    sendsTo: (first) => `Ваш контакт получит ${first}. Больше его никто не увидит.`,
    send: 'Отправить мой контакт',
    skip: 'Пропустить',
    doneTitle: (first) => `Готово! ${first} уже видит ваш контакт.`,
    doneSave: () => 'Сохранить контакт',
    doneSaved: () => 'Контакт сохранён',
    doneBack: () => 'Вернуться к визитке',
    changedMind: 'Передумали?',
    script: {
      linkCopied: 'Ссылка скопирована',
      openInBrowser: 'Откройте в браузере, чтобы сохранить',
      needName: 'Чтобы отправить, укажите имя.',
      needContact: 'Чтобы отправить, укажите телефон или Telegram.',
      invalidName: 'Проверьте имя.',
      invalidPhone: 'Проверьте номер телефона.',
      invalidTelegram: 'Проверьте имя пользователя Telegram: 5–32 буквы, цифры или _.',
      invalidMetAt: 'Сократите текст о месте знакомства.',
      sending: 'Отправка…',
      tooMany: 'Слишком много попыток. Повторите позже.',
      failed: 'Что-то пошло не так. Попробуйте ещё раз.',
      offline: 'Похоже, нет подключения к интернету. Попробуйте ещё раз.',
      removed: 'Ваш контакт удалён',
      cannotRemove: 'Этот контакт больше нельзя удалить здесь',
      removeFailed: 'Не удалось удалить контакт. Попробуйте ещё раз.',
    },
  },
  en: {
    ogLocale: 'en_US',
    description: 'Digital business card on Tanishly',
    inAppNotice: 'Open this page in your browser to save the contact.',
    copyLink: 'Copy link',
    contactDetails: 'Contact details',
    fieldLabel: {
      phone: 'phone',
      whatsapp: 'whatsapp',
      telegram: 'telegram',
      instagram: 'instagram',
      email: 'email',
      website: 'website',
      linkedin: 'linkedin',
      address: 'address',
    },
    phoneLabel: { mobile: 'mobile', work: 'work phone', home: 'home phone', other: 'other phone' },
    copy: 'Copy',
    copyAria: (label) => `Copy ${label}`,
    phoneCopied: 'Phone Copied',
    emailCopied: 'Email Copied',
    saveToContacts: 'Save to Contacts',
    exchange: (first) => `Exchange Contacts with ${first}`,
    sent: (first) => `Your contact was sent to ${first}.`,
    removeMine: 'Remove my contact',
    ctaTitle: 'Want a card like this?',
    ctaSubtitle: 'Create yours with Tanishly in 1 minute. Never lose a new contact again.',
    ctaButton: 'Create for free',
    androidWaitlist: 'iPhone only for now. We’ll let you know when Android is ready.',
    androidOnly: 'iPhone only for now.',
    notifyMe: 'Notify me',
    cardOwner: 'the card owner',
    foot: 'Made with Tanishly · Only public details are shown',
    sheetTitle: (first) => `Exchange contacts with ${first}`,
    sheetSubtitle: (first) => `Send yours and save ${first}’s in one step.`,
    name: 'Name',
    namePlaceholder: 'Your name',
    phone: 'Phone',
    telegram: 'Telegram',
    telegramPlaceholder: '@username',
    metAt: 'Met at',
    metAtPlaceholder: 'Where did we meet? Optional',
    phoneOrTelegram: 'Add a phone or Telegram — at least one.',
    sendsTo: (first) => `Your contact will be sent to ${first}. Only they will see it.`,
    send: 'Send my contact',
    skip: 'Skip',
    doneTitle: (first) => `Your contact was sent to ${first}`,
    doneSave: (first) => `Save ${first}’s Contact`,
    doneSaved: (first) => `${first}’s contact is saved`,
    doneBack: (first) => `Back to ${first}’s Card`,
    changedMind: 'Changed your mind?',
    script: {
      linkCopied: 'Link Copied',
      openInBrowser: 'Open in browser to save',
      needName: 'Add your name to send.',
      needContact: 'Add a phone or Telegram to send.',
      invalidName: 'Check your name.',
      invalidPhone: 'Enter a valid phone number.',
      invalidTelegram: 'Enter a Telegram username (5–32 letters, digits or _).',
      invalidMetAt: 'Make “Met at” shorter.',
      sending: 'Sending…',
      tooMany: 'Too many tries. Please try again later.',
      failed: 'Something went wrong. Please try again.',
      offline: 'You seem to be offline. Try again.',
      removed: 'Your contact was removed',
      cannotRemove: 'This contact can no longer be removed here',
      removeFailed: 'Could not remove your contact. Try again.',
    },
  },
};

export interface UnavailablePageText {
  unavailable: { title: string; body: string };
  notFound: { title: string; body: string };
  foot: string;
}

export const UNAVAILABLE_PAGE_TEXT: Record<Lang, UnavailablePageText> = {
  uz: {
    unavailable: {
      title: 'Bu vizitka hozircha mavjud emas.',
      body: 'Havola to‘xtatilgan yoki o‘chirilgan bo‘lishi mumkin. Egasidan yangisini so‘rang.',
    },
    notFound: {
      title: 'Bu vizitka topilmadi.',
      body: 'Havolani tekshiring yoki egasidan vizitkani qayta ulashishni so‘rang.',
    },
    foot: 'Tanishly’da yaratilgan',
  },
  ru: {
    unavailable: {
      title: 'Эта визитка сейчас недоступна.',
      body: 'Возможно, ссылку приостановили или удалили. Попросите у владельца новую.',
    },
    notFound: {
      title: 'Визитка не найдена.',
      body: 'Проверьте ссылку или попросите владельца поделиться визиткой ещё раз.',
    },
    foot: 'Сделано в Tanishly',
  },
  en: {
    unavailable: {
      title: 'This card isn’t available right now.',
      body: 'The link may be paused or removed. Ask the person for a new one.',
    },
    notFound: {
      title: 'We couldn’t find this card.',
      body: 'Check the link, or ask the person to share their card again.',
    },
    foot: 'Made with Tanishly',
  },
};
