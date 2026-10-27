// Privacy Policy, Terms of Use and Help for tanishly.app — App Store Connect needs a Privacy Policy URL
// and a Support URL. The privacy text describes what the app and this server actually do; keep it in
// step with Metly/PrivacyInfo.xcprivacy and the data model when either changes.
// Have a lawyer review these before the public launch (Uzbekistan's personal-data law applies).

export type LegalLang = 'uz' | 'ru' | 'en';
export type LegalDocKind = 'privacy' | 'terms' | 'help';

export interface LegalSection {
  heading: string;
  /** A paragraph, or a bullet list when it is an array. */
  body: (string | string[])[];
}

export interface LegalDoc {
  title: string;
  intro: string;
  sections: LegalSection[];
}

export const LEGAL_UPDATED = '2026-10-27';
export const SUPPORT_EMAIL = 'support@tanishly.app';

export const UI: Record<LegalLang, { updated: string; privacy: string; terms: string; help: string; contact: string; tagline: string; getApp: string; soon: string }> = {
  uz: {
    updated: 'Oxirgi yangilanish',
    privacy: 'Maxfiylik siyosati',
    terms: 'Foydalanish shartlari',
    help: 'Yordam',
    contact: 'Savollar bo‘lsa, yozing',
    tagline: 'Raqamli vizitka va tanishlaringiz uchun shaxsiy daftar.',
    getApp: 'App Store’dan yuklab olish',
    soon: 'Tez orada App Store’da',
  },
  ru: {
    updated: 'Последнее обновление',
    privacy: 'Политика конфиденциальности',
    terms: 'Условия использования',
    help: 'Помощь',
    contact: 'Если остались вопросы, напишите нам',
    tagline: 'Цифровая визитка и личный блокнот для ваших знакомств.',
    getApp: 'Скачать в App Store',
    soon: 'Скоро в App Store',
  },
  en: {
    updated: 'Last updated',
    privacy: 'Privacy Policy',
    terms: 'Terms of Use',
    help: 'Help',
    contact: 'Still have a question? Write to us',
    tagline: 'A digital business card and a private notebook for the people you meet.',
    getApp: 'Download on the App Store',
    soon: 'Coming soon to the App Store',
  },
};

const privacyEn: LegalDoc = {
  title: 'Privacy Policy',
  intro:
    'Tanishly helps you share a digital business card and remember the people you meet. This policy explains what we collect, why, who we share it with and how you control it. We do not sell your data, show ads or track you across other apps and websites.',
  sections: [
    {
      heading: 'What we collect',
      body: [
        [
          'Account: the identifier and email address Apple or Google gives us when you sign in (Apple may give us a private relay address).',
          'Profile and cards: your name, job title, company, photo, logo and the contact details you add, each with the privacy level you choose (Public, Connections or Private).',
          'People you save: the details of people you meet, the event, place and city where you met, your private notes, tags and follow-up reminders.',
          'Connect requests: who you sent a request to or received one from, and the card each of you shared.',
          'Device information: a push notification token, the app version, language and time zone (so reminders arrive at the right local time).',
          'Purchases: your subscription status from Apple. Apple processes the payment; we never see your card details.',
          'Telegram reminders (optional): the Telegram chat that you link to our bot.',
        ],
      ],
    },
    {
      heading: 'What stays on your iPhone',
      body: [
        [
          'Location is used only to fill in the city or place where you met someone. Only that text is saved; your coordinates never leave the device.',
          'The camera reads QR codes and paper business cards on the device. Card photos are not uploaded.',
          'Dictation runs on the device. Audio is not stored or sent anywhere.',
          'Your Contacts are not read or uploaded. The app only adds a person to Contacts when you tap Save.',
          'Your calendar is read on the device to suggest event names. Calendar data is not uploaded.',
        ],
      ],
    },
    {
      heading: 'Your public card page',
      body: [
        'Each card has a permanent link (tanishly.app/c/…). Anyone with the link sees only the fields you marked Public. Fields marked Connections are shown only in the app to people you have connected with. Private fields never leave your devices. You can pause all links or delete a card at any time.',
        'When someone opens your page we count views and saves using a salted hash of their connection, so we never store a visitor’s IP address. If a visitor chooses to share their contact back, the name and phone number or Telegram username they enter are given to you, and they get a link to remove them again.',
      ],
    },
    {
      heading: 'Why we use it',
      body: [
        [
          'To run the service: sync your data between your devices, publish your card pages, deliver connect requests and reminders.',
          'To keep the service safe: prevent abuse and fix errors (server logs never contain your notes or tokens).',
          'To provide Tanishly Pro when you subscribe.',
        ],
      ],
    },
    {
      heading: 'Who we share it with',
      body: [
        'Only with the service providers that run Tanishly for us, under contracts that limit them to that purpose:',
        [
          'our hosting and database provider and file storage (for photos and logos);',
          'Apple (Sign in with Apple, push notifications, the App Store and Apple Wallet) and Google (Sign in with Google);',
          'an email delivery provider (only to send you your data export);',
          'Telegram, only if you link the reminders bot.',
        ],
        'People you connect with see the card you chose to share with them. We disclose data to authorities only when the law requires it.',
      ],
    },
    {
      heading: 'How long we keep it',
      body: [
        'We keep your data while your account exists. When you delete a record it is removed from your devices and our servers; a short deletion marker is kept for up to 90 days so your other devices learn about it. When you delete your account, your profile, cards, people, notes and reminders are deleted from our servers right away, and your card links stop working. People you connected with keep the card you shared with them, as with a paper card.',
      ],
    },
    {
      heading: 'Your choices and rights',
      body: [
        [
          'Change what each card shows and who sees each field at any time.',
          'Download your data: Profile → Privacy & Data → Download My Data.',
          'Delete your account: Profile → Privacy & Data → Delete Account.',
          'Turn notifications, location and other permissions on or off in the iOS Settings app.',
        ],
        `For any other request, write to ${SUPPORT_EMAIL}. We answer within 30 days.`,
      ],
    },
    {
      heading: 'Children',
      body: ['Tanishly is not meant for children under 13, and we do not knowingly collect their data.'],
    },
    {
      heading: 'Changes',
      body: ['If we change this policy we will update the date above, and tell you in the app before important changes take effect.'],
    },
  ],
};

const privacyUz: LegalDoc = {
  title: 'Maxfiylik siyosati',
  intro:
    'Tanishly raqamli vizitkangizni ulashishga va tanishgan odamlaringizni eslab qolishga yordam beradi. Bu sahifada qaysi ma’lumotlarni yig‘ishimiz, nima uchun, kimga uzatishimiz va ularni qanday boshqarishingiz tushuntirilgan. Biz ma’lumotlaringizni sotmaymiz, reklama ko‘rsatmaymiz va sizni boshqa ilova va saytlarda kuzatmaymiz.',
  sections: [
    {
      heading: 'Qanday ma’lumotlarni yig‘amiz',
      body: [
        [
          'Akkaunt: Apple yoki Google orqali kirganingizda ular beradigan identifikator va email (Apple yashirin “relay” manzil berishi mumkin).',
          'Profil va kartalar: ismingiz, lavozimingiz, kompaniya, rasm, logotip va qo‘shgan kontaktlaringiz — har biri siz tanlagan maxfiylik darajasi bilan (Hammaga, Ulanganlarga yoki Shaxsiy).',
          'Saqlagan odamlaringiz: tanishgan odamlaringiz ma’lumotlari, qayerda va qaysi tadbirda tanishganingiz, shaxsiy eslatmalaringiz, teglar va follow-up eslatmalari.',
          'Ulanish so‘rovlari: kimga so‘rov yuborganingiz yoki kimdan olganingiz va har biringiz ulashgan karta.',
          'Qurilma ma’lumotlari: push-bildirishnoma tokeni, ilova versiyasi, til va vaqt mintaqasi (eslatmalar mahalliy vaqtda kelishi uchun).',
          'Xaridlar: Apple’dan obuna holati. To‘lovni Apple qayta ishlaydi, biz karta ma’lumotlaringizni ko‘rmaymiz.',
          'Telegram eslatmalari (ixtiyoriy): botimizga ulagan Telegram chatingiz.',
        ],
      ],
    },
    {
      heading: 'iPhone’ingizda qoladigan ma’lumotlar',
      body: [
        [
          'Joylashuv faqat tanishgan shahar yoki joyni yozib qo‘yish uchun ishlatiladi. Faqat shu matn saqlanadi, koordinatalaringiz qurilmadan chiqmaydi.',
          'Kamera QR kodlarni va qog‘oz vizitkalarni qurilmaning o‘zida o‘qiydi. Vizitka rasmlari serverga yuklanmaydi.',
          'Ovozli kiritish qurilmada ishlaydi. Audio saqlanmaydi va hech qayerga yuborilmaydi.',
          'Kontaktlaringiz o‘qilmaydi va yuklanmaydi. Ilova odamni faqat siz “Saqlash”ni bosganingizda Kontaktlarga qo‘shadi.',
          'Kalendaringiz tadbir nomlarini taklif qilish uchun qurilmada o‘qiladi va serverga yuklanmaydi.',
        ],
      ],
    },
    {
      heading: 'Kartangizning ochiq sahifasi',
      body: [
        'Har bir kartaning doimiy havolasi bor (tanishly.app/c/…). Havolasi bor odam faqat siz “Hammaga” deb belgilagan maydonlarni ko‘radi. “Ulanganlarga” maydonlari faqat ilovada, siz bilan ulangan odamlarga ko‘rinadi. Shaxsiy maydonlar qurilmalaringizdan hech qachon chiqmaydi. Istalgan payt barcha havolalarni to‘xtatib qo‘yishingiz yoki kartani o‘chirishingiz mumkin.',
        'Sahifangiz ochilganda ko‘rishlar va saqlashlar tashrifchi ulanishining tuzlangan xeshi orqali sanaladi, shuning uchun uning IP manzili saqlanmaydi. Tashrifchi o‘z kontaktini sizga qaytarib ulashsa, u kiritgan ism va telefon yoki Telegram foydalanuvchi nomi sizga beriladi, unga esa ularni o‘chirish havolasi beriladi.',
      ],
    },
    {
      heading: 'Nima uchun ishlatamiz',
      body: [
        [
          'Xizmatni ishlatish uchun: ma’lumotlarni qurilmalaringiz orasida sinxronlash, karta sahifalarini chop etish, ulanish so‘rovlari va eslatmalarni yetkazish.',
          'Xizmat xavfsizligi uchun: suiiste’molning oldini olish va xatolarni tuzatish (server loglarida eslatmalaringiz va tokenlar saqlanmaydi).',
          'Obuna bo‘lsangiz, Tanishly Pro’ni taqdim etish uchun.',
        ],
      ],
    },
    {
      heading: 'Kimga uzatamiz',
      body: [
        'Faqat Tanishly’ni biz uchun ishlatadigan xizmat ko‘rsatuvchilarga, ularni shu maqsad bilan cheklaydigan shartnomalar asosida:',
        [
          'hosting va ma’lumotlar bazasi provayderi hamda fayl ombori (rasm va logotiplar uchun);',
          'Apple (Apple bilan kirish, push-bildirishnomalar, App Store va Apple Wallet) va Google (Google bilan kirish);',
          'email yetkazish xizmati (faqat ma’lumotlaringiz arxivini yuborish uchun);',
          'Telegram — faqat eslatmalar botini ulasangiz.',
        ],
        'Siz bilan ulangan odamlar siz ulashishni tanlagan kartani ko‘radi. Ma’lumotlarni davlat organlariga faqat qonun talab qilganda beramiz.',
      ],
    },
    {
      heading: 'Qancha muddat saqlaymiz',
      body: [
        'Akkauntingiz mavjud ekan, ma’lumotlaringizni saqlaymiz. Biror yozuvni o‘chirsangiz, u qurilmalaringizdan va serverlarimizdan o‘chadi; boshqa qurilmalaringiz bilishi uchun qisqa o‘chirish belgisi 90 kungacha saqlanadi. Akkauntni o‘chirsangiz, profilingiz, kartalaringiz, odamlaringiz, eslatmalaringiz va follow-up’laringiz serverlarimizdan darhol o‘chiriladi, karta havolalaringiz ishlamay qoladi. Siz bilan ulangan odamlarda siz ularga ulashgan karta qoladi — xuddi qog‘oz vizitka kabi.',
      ],
    },
    {
      heading: 'Sizning tanlovingiz va huquqlaringiz',
      body: [
        [
          'Har bir karta nimani ko‘rsatishini va har bir maydonni kim ko‘rishini istalgan payt o‘zgartirishingiz mumkin.',
          'Ma’lumotlaringizni yuklab olish: Profile → Privacy & Data → Download My Data.',
          'Akkauntni o‘chirish: Profile → Privacy & Data → Delete Account.',
          'Bildirishnoma, joylashuv va boshqa ruxsatlarni iOS Sozlamalarida yoqib-o‘chirishingiz mumkin.',
        ],
        `Boshqa har qanday so‘rov bo‘yicha ${SUPPORT_EMAIL} manziliga yozing. 30 kun ichida javob beramiz.`,
      ],
    },
    {
      heading: 'Bolalar',
      body: ['Tanishly 13 yoshgacha bo‘lgan bolalar uchun mo‘ljallanmagan va biz ularning ma’lumotlarini ataylab yig‘maymiz.'],
    },
    {
      heading: 'O‘zgarishlar',
      body: ['Siyosatni o‘zgartirsak, yuqoridagi sanani yangilaymiz, muhim o‘zgarishlar kuchga kirishidan oldin esa ilovada xabar beramiz.'],
    },
  ],
};

const privacyRu: LegalDoc = {
  title: 'Политика конфиденциальности',
  intro:
    'Tanishly помогает делиться цифровой визиткой и помнить людей, с которыми вы познакомились. Здесь объясняется, какие данные мы собираем, зачем, кому передаём и как вы ими управляете. Мы не продаём ваши данные, не показываем рекламу и не отслеживаем вас в других приложениях и на сайтах.',
  sections: [
    {
      heading: 'Какие данные мы собираем',
      body: [
        [
          'Аккаунт: идентификатор и email, которые передают Apple или Google при входе (Apple может передать скрытый relay-адрес).',
          'Профиль и визитки: имя, должность, компания, фото, логотип и добавленные контакты — каждый с выбранным вами уровнем доступа (Всем, Контактам или Только мне).',
          'Сохранённые люди: данные людей, с которыми вы познакомились, мероприятие, место и город знакомства, ваши личные заметки, теги и напоминания.',
          'Запросы на обмен: кому вы отправили запрос или от кого получили, и визитка, которой поделился каждый.',
          'Данные устройства: токен push-уведомлений, версия приложения, язык и часовой пояс (чтобы напоминания приходили по местному времени).',
          'Покупки: статус подписки от Apple. Оплату обрабатывает Apple, данные вашей карты мы не видим.',
          'Напоминания в Telegram (по желанию): чат Telegram, который вы подключили к нашему боту.',
        ],
      ],
    },
    {
      heading: 'Что остаётся на вашем iPhone',
      body: [
        [
          'Геолокация используется только чтобы подставить город или место знакомства. Сохраняется только этот текст, координаты не покидают устройство.',
          'Камера считывает QR-коды и бумажные визитки на самом устройстве. Фото визиток не загружаются.',
          'Диктовка работает на устройстве. Аудио не сохраняется и никуда не отправляется.',
          'Ваши Контакты не читаются и не загружаются. Приложение добавляет человека в Контакты только когда вы нажимаете «Сохранить».',
          'Календарь читается на устройстве, чтобы подсказать названия мероприятий, и не загружается.',
        ],
      ],
    },
    {
      heading: 'Публичная страница визитки',
      body: [
        'У каждой визитки есть постоянная ссылка (tanishly.app/c/…). По ссылке видны только поля, отмеченные «Всем». Поля «Контактам» видны только в приложении людям, с которыми вы обменялись визитками. Поля «Только мне» никогда не покидают ваши устройства. Вы можете в любой момент приостановить все ссылки или удалить визитку.',
        'Когда страницу открывают, мы считаем просмотры и сохранения по солёному хешу соединения посетителя, поэтому его IP-адрес не хранится. Если посетитель решит поделиться своим контактом в ответ, введённые им имя и телефон или Telegram передаются вам, а он получает ссылку, чтобы удалить их.',
      ],
    },
    {
      heading: 'Зачем мы их используем',
      body: [
        [
          'Для работы сервиса: синхронизация между устройствами, публикация страниц визиток, доставка запросов и напоминаний.',
          'Для безопасности: защита от злоупотреблений и исправление ошибок (в логах сервера нет ваших заметок и токенов).',
          'Для Tanishly Pro, если вы оформили подписку.',
        ],
      ],
    },
    {
      heading: 'Кому мы их передаём',
      body: [
        'Только поставщикам услуг, которые обеспечивают работу Tanishly, по договорам, ограничивающим их этой целью:',
        [
          'хостинг и база данных, файловое хранилище (для фото и логотипов);',
          'Apple (вход через Apple, push-уведомления, App Store и Apple Wallet) и Google (вход через Google);',
          'сервис доставки email (только чтобы отправить архив ваших данных);',
          'Telegram — только если вы подключили бота напоминаний.',
        ],
        'Люди, с которыми вы обменялись визитками, видят визитку, которой вы решили поделиться. Государственным органам данные передаются только по требованию закона.',
      ],
    },
    {
      heading: 'Сколько мы их храним',
      body: [
        'Пока существует ваш аккаунт. Удалённая запись стирается с ваших устройств и наших серверов; короткая отметка об удалении хранится до 90 дней, чтобы о ней узнали другие ваши устройства. При удалении аккаунта профиль, визитки, люди, заметки и напоминания сразу удаляются с наших серверов, а ссылки визиток перестают работать. У людей, с которыми вы обменялись визитками, остаётся визитка, которой вы поделились, — как с бумажной.',
      ],
    },
    {
      heading: 'Ваш выбор и права',
      body: [
        [
          'В любой момент меняйте, что показывает визитка и кто видит каждое поле.',
          'Скачать свои данные: Profile → Privacy & Data → Download My Data.',
          'Удалить аккаунт: Profile → Privacy & Data → Delete Account.',
          'Уведомления, геолокацию и другие разрешения можно включить или выключить в Настройках iOS.',
        ],
        `По любым другим вопросам пишите на ${SUPPORT_EMAIL}. Мы отвечаем в течение 30 дней.`,
      ],
    },
    {
      heading: 'Дети',
      body: ['Tanishly не предназначен для детей младше 13 лет, и мы сознательно не собираем их данные.'],
    },
    {
      heading: 'Изменения',
      body: ['Если мы изменим политику, мы обновим дату выше, а о важных изменениях сообщим в приложении заранее.'],
    },
  ],
};

const termsEn: LegalDoc = {
  title: 'Terms of Use',
  intro: 'These terms apply when you use the Tanishly app and the tanishly.app website. By using Tanishly you agree to them.',
  sections: [
    {
      heading: 'Your account',
      body: [
        'You sign in with Apple or Google and are responsible for what happens in your account. Give accurate information on your cards, and only add other people’s details when you have a legitimate reason, such as having met them.',
      ],
    },
    {
      heading: 'Your content',
      body: [
        'Your cards, notes and contacts remain yours. You give us permission to store and show them only as needed to run the service — for example, to publish the fields you made Public on your card page. You can delete them at any time.',
      ],
    },
    {
      heading: 'Acceptable use',
      body: [
        'Do not use Tanishly to send spam, impersonate someone, collect data about people without their knowledge, publish illegal or offensive content, or attempt to break or overload the service. We may suspend accounts that do.',
      ],
    },
    {
      heading: 'Card links',
      body: [
        'Card links are permanent so printed QR codes keep working. A paused or deleted card shows an “unavailable” page; a deleted card’s link is never given to anyone else.',
      ],
    },
    {
      heading: 'Tanishly Pro',
      body: [
        'Pro is an auto-renewing subscription sold through the App Store. Payment is charged to your Apple Account and renews unless you turn it off at least 24 hours before the end of the period. Manage or cancel it in Settings → Apple Account → Subscriptions. Deleting the app or your account does not cancel a subscription. Refunds are handled by Apple.',
      ],
    },
    {
      heading: 'Availability and changes',
      body: [
        'We work to keep Tanishly available and your data safe, but the service is provided “as is”, without guarantees that it will always be uninterrupted or error-free. We may change or discontinue features; if we shut the service down we will give you notice and a way to export your data.',
      ],
    },
    {
      heading: 'Liability',
      body: [
        'To the extent the law allows, Tanishly is not liable for indirect losses, or for losses caused by information that users put on their cards. Nothing in these terms limits rights you have under consumer law.',
      ],
    },
    {
      heading: 'Ending',
      body: ['You can stop using Tanishly and delete your account at any time from the app.'],
    },
    {
      heading: 'Law and contact',
      body: [`These terms are governed by the laws of the Republic of Uzbekistan. Questions: ${SUPPORT_EMAIL}.`],
    },
  ],
};

const termsUz: LegalDoc = {
  title: 'Foydalanish shartlari',
  intro: 'Bu shartlar Tanishly ilovasi va tanishly.app saytidan foydalanganingizda amal qiladi. Tanishly’dan foydalanish orqali ularga rozilik bildirasiz.',
  sections: [
    {
      heading: 'Akkauntingiz',
      body: [
        'Siz Apple yoki Google orqali kirasiz va akkauntingizda sodir bo‘ladigan narsalar uchun javobgarsiz. Kartalaringizda to‘g‘ri ma’lumot bering, boshqalarning ma’lumotlarini esa faqat asosli sabab bo‘lganda qo‘shing — masalan, ular bilan tanishgan bo‘lsangiz.',
      ],
    },
    {
      heading: 'Sizning kontentingiz',
      body: [
        'Kartalaringiz, eslatmalaringiz va kontaktlaringiz sizniki bo‘lib qoladi. Siz bizga ularni faqat xizmatni ishlatish uchun zarur bo‘lgan darajada saqlash va ko‘rsatishga ruxsat berasiz — masalan, “Hammaga” deb belgilagan maydonlarni karta sahifangizda ko‘rsatish. Ularni istalgan payt o‘chirishingiz mumkin.',
      ],
    },
    {
      heading: 'Ruxsat etilgan foydalanish',
      body: [
        'Tanishly’dan spam yuborish, boshqa odam nomidan harakat qilish, odamlar haqida ularning bilmasdan ma’lumot to‘plash, noqonuniy yoki haqoratli kontent joylash yoki xizmatni buzishga yoki ortiqcha yuklashga urinish uchun foydalanmang. Bunday akkauntlarni to‘xtatib qo‘yishimiz mumkin.',
      ],
    },
    {
      heading: 'Karta havolalari',
      body: [
        'Chop etilgan QR kodlar ishlashda davom etishi uchun karta havolalari doimiy. To‘xtatilgan yoki o‘chirilgan karta “mavjud emas” sahifasini ko‘rsatadi; o‘chirilgan karta havolasi hech qachon boshqa birovga berilmaydi.',
      ],
    },
    {
      heading: 'Tanishly Pro',
      body: [
        'Pro — App Store orqali sotiladigan avtomatik yangilanadigan obuna. To‘lov Apple akkauntingizdan olinadi va davr tugashidan kamida 24 soat oldin o‘chirmasangiz, avtomatik yangilanadi. Obunani Sozlamalar → Apple akkaunt → Obunalar bo‘limida boshqaring yoki bekor qiling. Ilovani yoki akkauntni o‘chirish obunani bekor qilmaydi. Pulni qaytarish masalasini Apple hal qiladi.',
      ],
    },
    {
      heading: 'Xizmat mavjudligi va o‘zgarishlar',
      body: [
        'Tanishly’ning ishlashi va ma’lumotlaringiz xavfsizligi uchun harakat qilamiz, lekin xizmat “boricha” taqdim etiladi va uning doim uzluksiz yoki xatosiz ishlashiga kafolat berilmaydi. Funksiyalarni o‘zgartirishimiz yoki to‘xtatishimiz mumkin; xizmatni yopsak, oldindan xabar beramiz va ma’lumotlaringizni eksport qilish imkonini qoldiramiz.',
      ],
    },
    {
      heading: 'Javobgarlik',
      body: [
        'Qonun ruxsat bergan darajada Tanishly bilvosita zararlar yoki foydalanuvchilar o‘z kartalariga joylagan ma’lumotlar tufayli yetgan zararlar uchun javobgar emas. Bu shartlar iste’molchilar huquqlarini himoya qilish qonunchiligi bo‘yicha huquqlaringizni cheklamaydi.',
      ],
    },
    {
      heading: 'Foydalanishni tugatish',
      body: ['Tanishly’dan foydalanishni istalgan payt to‘xtatib, akkauntingizni ilovaning o‘zidan o‘chirishingiz mumkin.'],
    },
    {
      heading: 'Qonun va aloqa',
      body: [`Bu shartlar O‘zbekiston Respublikasi qonunchiligiga bo‘ysunadi. Savollar uchun: ${SUPPORT_EMAIL}.`],
    },
  ],
};

const termsRu: LegalDoc = {
  title: 'Условия использования',
  intro: 'Эти условия действуют при использовании приложения Tanishly и сайта tanishly.app. Пользуясь Tanishly, вы соглашаетесь с ними.',
  sections: [
    {
      heading: 'Ваш аккаунт',
      body: [
        'Вы входите через Apple или Google и отвечаете за то, что происходит в вашем аккаунте. Указывайте на визитках достоверные данные, а данные других людей добавляйте только при законном основании — например, если вы с ними познакомились.',
      ],
    },
    {
      heading: 'Ваш контент',
      body: [
        'Ваши визитки, заметки и контакты остаются вашими. Вы разрешаете нам хранить и показывать их только в той мере, в какой это нужно для работы сервиса, — например, показывать поля «Всем» на странице визитки. Вы можете удалить их в любой момент.',
      ],
    },
    {
      heading: 'Допустимое использование',
      body: [
        'Не используйте Tanishly для спама, выдачи себя за другого человека, сбора данных о людях без их ведома, публикации незаконного или оскорбительного контента или попыток нарушить работу сервиса. Такие аккаунты мы можем заблокировать.',
      ],
    },
    {
      heading: 'Ссылки визиток',
      body: [
        'Ссылки визиток постоянны, чтобы напечатанные QR-коды продолжали работать. Приостановленная или удалённая визитка показывает страницу «недоступно»; ссылка удалённой визитки никогда не передаётся другому человеку.',
      ],
    },
    {
      heading: 'Tanishly Pro',
      body: [
        'Pro — автоматически продлеваемая подписка, продаваемая через App Store. Оплата списывается с вашего Apple-аккаунта и продлевается, если не отключить её не позднее чем за 24 часа до конца периода. Управлять подпиской или отменить её можно в Настройки → Apple-аккаунт → Подписки. Удаление приложения или аккаунта не отменяет подписку. Возвраты обрабатывает Apple.',
      ],
    },
    {
      heading: 'Доступность и изменения',
      body: [
        'Мы стараемся, чтобы Tanishly работал стабильно и ваши данные были в безопасности, но сервис предоставляется «как есть», без гарантий бесперебойной и безошибочной работы. Мы можем менять или отключать функции; если сервис будет закрыт, мы предупредим заранее и дадим возможность выгрузить данные.',
      ],
    },
    {
      heading: 'Ответственность',
      body: [
        'В пределах, допустимых законом, Tanishly не отвечает за косвенные убытки и за убытки, вызванные информацией, которую пользователи размещают на своих визитках. Эти условия не ограничивают ваши права по законодательству о защите прав потребителей.',
      ],
    },
    {
      heading: 'Прекращение',
      body: ['Вы можете в любой момент перестать пользоваться Tanishly и удалить аккаунт прямо в приложении.'],
    },
    {
      heading: 'Право и контакты',
      body: [`Эти условия регулируются законодательством Республики Узбекистан. Вопросы: ${SUPPORT_EMAIL}.`],
    },
  ],
};

const helpEn: LegalDoc = {
  title: 'Help',
  intro: 'Answers to the most common questions about Tanishly.',
  sections: [
    {
      heading: 'How do I share my card?',
      body: ['Open the app and tap Show QR — the other person scans it with their camera. You can also tap Share to send the link, add the card to Apple Wallet, or use Connect to swap cards with someone nearby who also has Tanishly.'],
    },
    {
      heading: 'Who sees which details?',
      body: [
        [
          'Public — anyone with your card link or QR code.',
          'Connections — only people you have swapped cards with in the app.',
          'Private — only you; never shown on a card.',
        ],
        'Set this for each field in Profile → Contact Details. Each card can also hide fields it doesn’t need.',
      ],
    },
    {
      heading: 'I printed my QR code. Will it keep working?',
      body: ['Yes. Card links never change. If you pause your links or delete the card, the page shows that the card is unavailable, and pausing can be undone at any time.'],
    },
    {
      heading: 'How do I delete a card or my account?',
      body: ['Delete a card from its menu (…) on the Home screen. Delete your account in Profile → Privacy & Data → Delete Account; this removes your data from our servers. If you subscribed to Pro, cancel the subscription in iOS Settings as well.'],
    },
    {
      heading: 'How do I restore Pro on a new iPhone?',
      body: ['Sign in with the same Apple or Google account, then open Profile → Tanishly Pro → Restore Purchases.'],
    },
    {
      heading: 'Can I get reminders in Telegram?',
      body: ['Yes. In Profile → Notifications, choose Telegram and follow the link to our bot. You can switch back to push notifications at any time.'],
    },
  ],
};

const helpUz: LegalDoc = {
  title: 'Yordam',
  intro: 'Tanishly haqidagi eng ko‘p beriladigan savollarga javoblar.',
  sections: [
    {
      heading: 'Kartamni qanday ulashaman?',
      body: ['Ilovani oching va “Show QR”ni bosing — qarshingizdagi odam uni kamerasi bilan skanerlaydi. “Share” orqali havolani yuborishingiz, kartani Apple Wallet’ga qo‘shishingiz yoki “Connect” bilan yoningizdagi Tanishly foydalanuvchisi bilan karta almashishingiz ham mumkin.'],
    },
    {
      heading: 'Qaysi ma’lumotni kim ko‘radi?',
      body: [
        [
          'Hammaga — karta havolangiz yoki QR kodingiz bor har kim.',
          'Ulanganlarga — faqat ilovada siz bilan karta almashgan odamlar.',
          'Shaxsiy — faqat siz; kartada hech qachon ko‘rinmaydi.',
        ],
        'Buni har bir maydon uchun Profile → Contact Details bo‘limida belgilaysiz. Har bir karta kerak bo‘lmagan maydonlarni yashirishi ham mumkin.',
      ],
    },
    {
      heading: 'QR kodimni chop etdim. U ishlashda davom etadimi?',
      body: ['Ha. Karta havolalari hech qachon o‘zgarmaydi. Havolalarni to‘xtatsangiz yoki kartani o‘chirsangiz, sahifada karta mavjud emasligi ko‘rsatiladi; to‘xtatishni istalgan payt bekor qilish mumkin.'],
    },
    {
      heading: 'Kartani yoki akkauntni qanday o‘chiraman?',
      body: ['Kartani Home ekranidagi uning menyusidan (…) o‘chiring. Akkauntni Profile → Privacy & Data → Delete Account orqali o‘chiring; bu ma’lumotlaringizni serverlarimizdan o‘chiradi. Pro’ga obuna bo‘lgan bo‘lsangiz, obunani iOS Sozlamalarida ham bekor qiling.'],
    },
    {
      heading: 'Yangi iPhone’da Pro’ni qanday tiklayman?',
      body: ['Xuddi o‘sha Apple yoki Google akkaunti bilan kiring, keyin Profile → Tanishly Pro → Restore Purchases’ni oching.'],
    },
    {
      heading: 'Eslatmalarni Telegram’da olsam bo‘ladimi?',
      body: ['Ha. Profile → Notifications bo‘limida Telegram’ni tanlang va botimizga havola orqali o‘ting. Istalgan payt push-bildirishnomalarga qaytishingiz mumkin.'],
    },
  ],
};

const helpRu: LegalDoc = {
  title: 'Помощь',
  intro: 'Ответы на самые частые вопросы о Tanishly.',
  sections: [
    {
      heading: 'Как поделиться визиткой?',
      body: ['Откройте приложение и нажмите Show QR — собеседник сканирует код камерой. Также можно нажать Share и отправить ссылку, добавить визитку в Apple Wallet или через Connect обменяться визитками с человеком рядом, у которого тоже есть Tanishly.'],
    },
    {
      heading: 'Кто видит какие данные?',
      body: [
        [
          'Всем — любой, у кого есть ссылка или QR-код визитки.',
          'Контактам — только люди, с которыми вы обменялись визитками в приложении.',
          'Только мне — только вы; на визитке никогда не показывается.',
        ],
        'Это настраивается для каждого поля в Profile → Contact Details. Каждая визитка также может скрывать ненужные поля.',
      ],
    },
    {
      heading: 'Я напечатал QR-код. Он будет работать?',
      body: ['Да. Ссылки визиток никогда не меняются. Если приостановить ссылки или удалить визитку, страница покажет, что визитка недоступна; приостановку можно отменить в любой момент.'],
    },
    {
      heading: 'Как удалить визитку или аккаунт?',
      body: ['Визитку удалите через её меню (…) на главном экране. Аккаунт — в Profile → Privacy & Data → Delete Account; данные будут удалены с наших серверов. Если вы оформили Pro, отмените подписку и в Настройках iOS.'],
    },
    {
      heading: 'Как восстановить Pro на новом iPhone?',
      body: ['Войдите с тем же аккаунтом Apple или Google и откройте Profile → Tanishly Pro → Restore Purchases.'],
    },
    {
      heading: 'Можно получать напоминания в Telegram?',
      body: ['Да. В Profile → Notifications выберите Telegram и перейдите по ссылке к нашему боту. Вернуться к push-уведомлениям можно в любой момент.'],
    },
  ],
};

export const LEGAL: Record<LegalDocKind, Record<LegalLang, LegalDoc>> = {
  privacy: { en: privacyEn, uz: privacyUz, ru: privacyRu },
  terms: { en: termsEn, uz: termsUz, ru: termsRu },
  help: { en: helpEn, uz: helpUz, ru: helpRu },
};
