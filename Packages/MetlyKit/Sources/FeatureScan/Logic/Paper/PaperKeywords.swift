import Foundation

/// Word lists behind the paper-card heuristics (English, Russian, Uzbek Latin). All lower-case.
/// Stems are matched as word prefixes ("руководител" matches "руководитель"), so keep them specific;
/// stems of four letters or fewer must match a whole word ("lab" never matches "Labib").
nonisolated enum PaperKeywords {
    // MARK: Job titles

    /// A single one of these makes a line a job title.
    static let strongTitleStems: [String] = [
        // English
        "ceo", "cto", "cfo", "coo", "cmo", "cpo", "cio", "chro", "vp", "svp", "evp", "founder", "co-founder", "cofounder",
        "owner", "president", "chairman", "chairwoman", "director", "manager", "head", "lead", "chief", "officer",
        "engineer", "developer", "designer", "architect", "analyst", "consultant", "specialist", "advisor", "adviser",
        "associate", "assistant", "coordinator", "executive", "representative", "recruiter", "accountant", "lawyer",
        "attorney", "professor", "teacher", "scientist", "researcher", "administrator", "supervisor", "strategist",
        "marketer", "editor", "journalist", "photographer", "producer", "entrepreneur", "intern", "trainee", "deputy",
        "programmer", "partner", "investor", "doctor",
        // Russian
        "директор", "генеральн", "менеджер", "руководител", "начальник", "инженер", "разработчик", "программист",
        "дизайнер", "основател", "сооснователь", "специалист", "консультант", "аналитик", "бухгалтер", "юрист",
        "адвокат", "председател", "заместител", "партнер", "партнёр", "президент", "владел", "управляющ",
        "координатор", "администратор", "маркетолог", "представител", "советник", "эксперт", "ректор", "декан",
        "преподавател", "врач", "архитектор", "продюсер", "редактор", "глава", "вице",
        // Uzbek (Latin)
        "direktor", "rahbar", "boshliq", "boshlig", "boshqaruvchi", "menejer", "muhandis", "dasturchi", "dizayner", "asoschi",
        "hammuassis", "mutaxassis", "maslahatchi", "tahlilchi", "buxgalter", "yurist", "rais", "o'rinbosar",
        "o‘rinbosar", "hamkor", "egasi", "prezident", "koordinator", "administrator", "marketolog", "vakil", "ekspert",
        "rektor", "dekan", "o'qituvchi", "o‘qituvchi", "shifokor", "arxitektor", "muharrir", "prodyuser", "yetakchi",
        // More occupations (EN / RU / UZ)
        "translator", "interpreter", "tarjimon", "переводчик", "hisobchi", "bookkeeper", "agent", "broker", "operator",
        "mentor", "coach", "trainer", "murabbiy", "stylist", "stilist", "secretary", "kotib", "секретар", "dispatcher",
        "sotuvchi", "seller", "продавец", "fotograf", "фотограф", "jurnalist", "журналист", "muxbir", "nurse",
        "hamshira", "медсестра", "pharmacist", "farmatsevt", "фармацевт", "surgeon", "jarroh", "хирург", "dentist",
        "stomatolog", "стоматолог", "tutor", "artist", "rassom", "художник", "copywriter", "копирайтер", "chef",
        "oshpaz", "повар", "pilot", "notary", "notarius", "нотариус", "auditor", "аудитор", "economist", "iqtisodchi",
        "экономист", "логист", "realtor", "rieltor", "риэлтор", "makler", "маклер", "технолог", "texnolog",
        "technologist", "mechanic", "mexanik", "механик", "electrician", "elektrik", "электрик", "barista",
        "кассир", "kassir", "cashier", "officer", "ofitser", "hakam", "sudya", "судья", "prokuror", "прокурор",
        "dotsent", "доцент", "lecturer", "kardiolog", "кардиолог", "nevrolog", "невролог", "psixolog", "психолог",
        "pediatr", "педиатр", "terapevt", "терапевт", "jarroh", "ginekolog", "гинеколог", "urolog", "уролог",
    ]

    /// Modifiers that only count together with another hint ("Senior", "Sales", "Bosh").
    static let weakTitleStems: [String] = [
        "senior", "junior", "principal", "staff", "general", "managing", "technical", "creative", "marketing", "sales",
        "product", "operations", "business", "development", "hr", "pm", "qa", "devops", "ux", "ui", "frontend",
        "backend", "full-stack", "fullstack",
        "главн", "ведущ", "старш", "младш", "исполнительн", "коммерческ", "технич", "финансов", "отдел", "продаж",
        "маркетинг",
        "bosh", "katta", "bo'lim", "bo‘lim", "savdo", "moliya", "loyiha",
        "regional", "hududiy", "региональн", "client", "account", "key", "customer", "support", "mijoz", "клиент",
        "kredit", "кредит", "it", "data", "brand", "content", "digital", "smm", "seo", "legal", "huquq", "правов",
    ]

    // MARK: Companies

    /// Legal forms, matched as whole tokens.
    static let legalForms: Set<String> = [
        "llc", "inc", "ltd", "llp", "plc", "gmbh", "corp", "co", "jsc", "ojsc", "cjsc", "ag", "bv", "oy",
        "mchj", "xk", "aj", "qk", "ooo", "ооо", "оао", "зао", "пао", "ао", "ип", "тоо", "мчж", "хк",
        "xab", "atb", "aatb", "dk", "ук", "атб", "аж", "хаб", "pte", "sarl", "srl",
    ]

    /// Company nouns, matched as word prefixes.
    static let companyStems: [String] = [
        "group", "bank", "holding", "technologies", "technology", "tech", "solutions", "labs", "lab", "studio",
        "agency", "systems", "consulting", "capital", "ventures", "media", "market", "pharm", "motors", "university",
        "institute", "academy", "foundation", "company", "corporation", "software", "digital", "logistics", "trade",
        "invest", "services", "production", "express", "telecom", "networks", "soft", "industries", "enterprises",
        "international", "clinic", "hotel", "restaurant", "school", "bureau", "center", "centre",
        "банк", "групп", "холдинг", "технолог", "систем", "решени", "медиа", "маркет", "университет", "академи",
        "институт", "компани", "корпораци", "фонд", "центр", "клиник", "гостиниц", "студи", "агентств",
        "лаборатори", "бюро", "сервис", "трейд", "инвест",
        "kompaniya", "korporatsiya", "universitet", "akademiya", "markaz", "klinika", "mehmonxona", "maktab",
        "sanoat", "servis", "fond", "banki", "банка",
        "electronics", "textile", "tekstil", "текстиль", "construction", "qurilish", "строй", "insurance",
        "sug'urta", "страхов", "pharma", "фарма", "avto", "авто", "food", "foods", "travel", "energy", "энерг",
        "finance", "finans", "финанс", "leasing", "lizing", "лизинг", "partners", "associates", "studios", "print",
        "realty", "estate", "mebel", "мебель", "furniture", "beauty", "salon", "салон", "cafe", "кафе", "restoran",
        "ресторан", "hospital", "shifoxona", "dorixona", "аптек", "pharmacy", "apteka", "lyceum", "litsey", "лицей",
        "college", "kollej", "колледж", "uyushma", "ассоциац", "association", "agentligi", "vazirlig", "министерств",
        "ministry", "committee", "комитет", "hokimlig", "хокимият", "boshqarma", "управлени", "inc", "llc",
    ]

    /// Free email providers — their domain says nothing about the company.
    static let freeMailDomains: Set<String> = [
        "gmail", "googlemail", "mail", "yandex", "inbox", "bk", "list", "outlook", "hotmail", "live", "icloud", "me",
        "yahoo", "proton", "protonmail", "rambler", "umail", "aol", "gmx",
    ]

    // MARK: Taglines

    /// A line starting with one of these is a slogan ("Your trusted partner…", "Мы строим будущее").
    static let taglineLeads: Set<String> = [
        "your", "we", "our", "мы", "ваш", "ваша", "ваше", "наш", "наша",
        "для", "лучш", "biz", "sizning", "bizning", "sizga", "eng", "har", "barcha",
    ]

    // MARK: Names

    /// Surname / patronymic endings (Uzbek, Russian, wider region).
    static let surnameSuffixes: [String] = [
        "ov", "ova", "ev", "eva", "yev", "yeva", "iev", "ieva", "in", "ina", "sky", "skiy", "skaya", "ski", "enko",
        "yan", "dze", "shvili", "zoda", "zade", "ovich", "evich", "ovna", "evna", "ichna",
        "ов", "ова", "ев", "ева", "ин", "ина", "ский", "ская", "енко", "ович", "евич", "овна", "евна", "ична", "зода",
    ]

    /// Lower-case name particles allowed inside a full name ("Akmal o'g'li", "van Dijk").
    static let nameParticles: Set<String> = [
        "o'g'li", "o‘g‘li", "og'li", "ugli", "o'gli", "qizi", "kizi", "угли", "кизи", "van", "von", "de", "da", "di",
        "la", "le", "bin", "ibn", "al", "el",
    ]

    // MARK: Addresses

    /// Words that make a line an address or a location rather than a name, title or company.
    static let locationWords: Set<String> = [
        "tashkent", "toshkent", "uzbekistan", "o'zbekiston", "o‘zbekiston", "samarkand", "samarqand", "bukhara",
        "buxoro", "andijan", "andijon", "namangan", "fergana", "farg'ona", "nukus", "khiva", "xiva", "moscow", "almaty",
        "astana", "bishkek", "dushanbe", "dubai", "london", "istanbul", "ташкент", "узбекистан", "самарканд",
        "бухара", "москва", "алматы", "republic", "respublikasi", "республика", "city", "shahri", "город", "region",
        "viloyati", "область",
    ]

    static let streetWords: Set<String> = [
        "street", "st", "str", "avenue", "ave", "road", "rd", "floor", "office", "suite", "building", "blvd",
        "ko'chasi", "ko‘chasi", "kuchasi", "mahalla", "tumani", "uy", "xonadon", "qavat", "ул", "улица", "пр",
        "проспект", "дом", "д", "кв", "офис", "этаж", "район", "мкр", "пер", "переулок",
    ]

    /// Street words that mark an address even without a number.
    static let streetNames: Set<String> = [
        "street", "avenue", "ko'chasi", "ko‘chasi", "kuchasi", "mahallasi", "tumani", "улица", "проспект", "переулок",
    ]
}
