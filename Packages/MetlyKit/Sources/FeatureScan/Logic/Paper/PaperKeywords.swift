import Foundation

/// Word lists behind the paper-card heuristics (English, Russian, Uzbek Latin). All lower-case.
/// Stems are matched as word prefixes ("руководител" matches "руководитель"), so keep them specific.
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
    ]

    /// Modifiers that only count together with another hint ("Senior", "Sales", "Bosh").
    static let weakTitleStems: [String] = [
        "senior", "junior", "principal", "staff", "general", "managing", "technical", "creative", "marketing", "sales",
        "product", "operations", "business", "development", "hr", "pm", "qa", "devops", "ux", "ui", "frontend",
        "backend", "full-stack", "fullstack",
        "главн", "ведущ", "старш", "младш", "исполнительн", "коммерческ", "технич", "финансов", "отдел", "продаж",
        "маркетинг",
        "bosh", "katta", "bo'lim", "bo‘lim", "savdo", "moliya", "loyiha",
    ]

    // MARK: Companies

    /// Legal forms, matched as whole tokens.
    static let legalForms: Set<String> = [
        "llc", "inc", "ltd", "llp", "plc", "gmbh", "corp", "co", "jsc", "ojsc", "cjsc", "ag", "bv", "oy",
        "mchj", "xk", "aj", "qk", "ooo", "ооо", "оао", "зао", "пао", "ао", "ип", "тоо", "мчж", "хк",
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
        "kompaniya", "korporatsiya", "universitet", "akademiya", "markazi", "klinika", "mehmonxona", "maktab",
        "sanoat", "servis", "fond",
    ]

    /// Free email providers — their domain says nothing about the company.
    static let freeMailDomains: Set<String> = [
        "gmail", "googlemail", "mail", "yandex", "inbox", "bk", "list", "outlook", "hotmail", "live", "icloud", "me",
        "yahoo", "proton", "protonmail", "rambler", "umail", "aol", "gmx",
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

    /// Common given names — a strong hint that a line is the person's name.
    static let givenNames: Set<String> = [
        "aziza", "kamila", "kamola", "sardor", "bekzod", "nodira", "dilnoza", "jasur", "madina", "timur", "shoxruh",
        "shohruh", "rustam", "akmal", "dilshod", "javohir", "malika", "gulnora", "sherzod", "bobur", "aziz", "alisher",
        "nigora", "zarina", "sevara", "ulugbek", "otabek", "farrux", "farrukh", "jamshid", "lola", "islom", "anvar",
        "sanjar", "laziz", "shahzod", "nilufar", "dildora", "umid", "sarvar", "abdulla", "muhammad", "mohammed",
        "kamol", "ravshan", "temur", "yulduz", "feruza", "munisa", "shaxnoza", "shakhnoza", "behruz", "jahongir",
        "alexander", "aleksandr", "sergey", "sergei", "ivan", "dmitry", "dmitriy", "andrey", "andrei", "alexey",
        "elena", "olga", "anna", "maria", "natalia", "irina", "ekaterina", "tatiana", "pavel", "nikolay", "mikhail",
        "john", "michael", "david", "james", "robert", "sarah", "emily", "jessica", "daniel", "thomas", "laura",
        "александр", "сергей", "иван", "дмитрий", "андрей", "алексей", "елена", "ольга", "анна", "мария", "наталья",
        "ирина", "екатерина", "татьяна", "павел", "николай", "михаил", "азиза", "камила", "сардор", "тимур", "рустам",
        "дильноза", "мадина", "джасур", "бекзод", "нодира", "шохрух", "акмал", "алишер",
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
