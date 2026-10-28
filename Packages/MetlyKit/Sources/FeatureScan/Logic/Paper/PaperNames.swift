import Foundation

/// Personal-name dictionaries for the paper-card heuristics: common given names and surnames met on
/// cards in Uzbekistan (Uzbek, Russian, Korean, Kazakh, Tajik) and English-speaking countries, in
/// Latin and Cyrillic. Lower-case, apostrophes as "'". A hit is strong evidence that a line is a
/// person's name rather than a brand.
nonisolated enum PaperNames {
    static func isGivenName(_ word: String) -> Bool {
        givenNames.contains(word) || givenNames.contains(word.replacingOccurrences(of: "'", with: ""))
    }

    static func isSurname(_ word: String) -> Bool {
        surnames.contains(word)
            || PaperKeywords.surnameSuffixes.contains { word.count > $0.count + 2 && word.hasSuffix($0) }
    }

    static let givenNames: Set<String> = uzbekMale.union(uzbekFemale).union(russian).union(english).union(cyrillic)

    private static let uzbekMale: Set<String> = [
        "abbos", "abdulaziz", "abdulla", "abdullah", "abdurahmon", "abdurashid", "abror", "adham", "akbar", "akmal",
        "akrom", "alisher", "anvar", "asad", "asror", "aziz", "azizbek", "azamat", "bahodir", "bakhodir", "baxtiyor",
        "bakhtiyor", "bekzod", "bekhzod", "behzod", "bobur", "botir", "davron", "dilmurod", "dilshod", "doniyor",
        "dostonbek", "elbek", "eldor", "elyor", "erkin", "farhod", "farkhod", "farrux", "farrukh", "fazliddin",
        "g'ayrat", "hamid", "hasan", "husan", "husniddin", "ibrohim", "ikrom", "ilhom", "ilyos", "islom", "islombek",
        "ismoil", "jahongir", "jaloliddin", "jamshid", "jasur", "javlon", "javohir", "kamol", "kamoliddin", "karim",
        "komil", "laziz", "lochin", "mahmud", "mansur", "mirjalol", "muhammad", "muhammadali", "murod", "nodir",
        "nodirbek", "nurbek", "nuriddin", "odil", "olim", "otabek", "oybek", "qodir", "rahim", "rashid", "rasul",
        "ravshan", "rustam", "rustambek", "sanjar", "sardor", "sarvar", "shavkat", "sherzod", "shohruh", "shoxrux",
        "shoxruh", "shuhrat", "shukhrat", "sirojiddin", "sobir", "sunnat", "temur", "timur", "tohir", "ulug'bek",
        "ulugbek", "umid", "xurshid", "khurshid", "yusuf", "zafar", "ziyod", "zokir", "shahzod", "behruz", "abdulvohid",
        "ahmad", "ahmed", "ali", "mohammed", "muhammadjon", "nozim", "jasurbek", "sanjarbek", "sherali", "ulmas",
        "zuhriddin", "jahon", "baxrom", "bahrom", "mirzo", "obid", "shamsiddin", "zohid", "asilbek", "diyorbek",
    ]

    private static let uzbekFemale: Set<String> = [
        "aziza", "barno", "charos", "dildora", "dilfuza", "dilnoza", "dilorom", "diyora", "durdona", "farangiz",
        "feruza", "firuza", "gulbahor", "gulchehra", "gulnora", "gulnoza", "gulshan", "hilola", "kamila", "kamola",
        "lobar", "lola", "madina", "maftuna", "malika", "marjona", "mavluda", "mohinur", "mohira", "mubina", "munisa",
        "muslima", "nargiza", "nasiba", "nigora", "nilufar", "nodira", "nozima", "oydin", "ozoda", "rayhona",
        "robiya", "sabina", "saida", "sarvinoz", "sevara", "sevinch", "shahnoza", "shaxnoza", "shakhnoza",
        "shahzoda", "shoira", "sitora", "umida", "xurshida", "yulduz", "zarina", "zebo", "ziyoda", "zuhra", "zulfiya",
        "rano", "dilbar", "gavhar", "guli", "iroda", "laylo", "malohat", "mukhlisa", "muxlisa", "nafisa", "nozila",
        "oysha", "parizod", "sanobar", "shirin", "zilola", "zarnigor", "madinabonu",
    ]

    private static let russian: Set<String> = [
        "aleksandr", "alexander", "aleksey", "alexey", "alexei", "anatoliy", "andrey", "andrei", "anton", "artem",
        "artyom", "boris", "denis", "dmitriy", "dmitry", "evgeniy", "yevgeniy", "evgeny", "igor", "ilya", "ivan",
        "kirill", "konstantin", "maksim", "maxim", "mikhail", "nikita", "nikolay", "nikolai", "oleg", "pavel", "roman",
        "ruslan", "sergey", "sergei", "stanislav", "vadim", "valeriy", "viktor", "victor", "vitaliy", "vladimir",
        "vladislav", "vyacheslav", "yuriy", "yury", "yuri", "alena", "alyona", "alina", "alla", "anastasia",
        "anastasiya", "daria", "darya", "ekaterina", "yekaterina", "elena", "yelena", "elizaveta", "galina", "inna",
        "irina", "kristina", "ksenia", "kseniya", "larisa", "lyudmila", "marina", "mariya", "natalia", "natalya",
        "nadezhda", "olga", "oksana", "polina", "svetlana", "tatiana", "tatyana", "valentina", "valeria", "vera",
        "viktoriya", "victoria", "yulia", "yuliya", "julia", "gennadiy", "grigoriy", "leonid", "arkadiy", "eduard",
    ]

    private static let english: Set<String> = [
        "james", "john", "robert", "michael", "william", "david", "richard", "joseph", "thomas", "charles",
        "christopher", "daniel", "matthew", "anthony", "mark", "paul", "steven", "andrew", "kevin", "brian", "george",
        "edward", "peter", "mary", "patricia", "jennifer", "linda", "elizabeth", "barbara", "susan", "jessica",
        "sarah", "karen", "nancy", "lisa", "emily", "emma", "olivia", "sophia", "laura", "rachel", "anna", "maria",
        "kate", "alex", "chris", "sam", "tom", "ben", "jack", "oliver", "lucas", "noah", "ethan", "wei", "ming",
        "jun", "yan", "hui", "lei", "min", "ji", "hyun", "soo", "jin", "mohamed", "omar", "fatima", "aisha",
    ]

    private static let cyrillic: Set<String> = [
        "александр", "алексей", "андрей", "антон", "артём", "артем", "борис", "вадим", "виктор", "владимир", "дмитрий",
        "денис", "евгений", "иван", "игорь", "илья", "кирилл", "константин", "максим", "михаил", "никита", "николай",
        "олег", "павел", "роман", "руслан", "сергей", "юрий", "алина", "анастасия", "анна", "валентина", "галина",
        "дарья", "екатерина", "елена", "ирина", "кристина", "ксения", "людмила", "марина", "мария", "наталья",
        "надежда", "ольга", "оксана", "светлана", "татьяна", "юлия", "азиза", "акмал", "алишер", "анвар", "бахтиёр",
        "бекзод", "бобур", "гулнора", "даврон", "дильноза", "дилноза", "дилшод", "дильшод", "жасур", "джасур",
        "жамшид", "джамшид", "зарина", "камила", "камола", "лола", "мадина", "малика", "нигора", "нодира", "отабек",
        "равшан", "рустам", "сардор", "санжар", "севара", "тимур", "темур", "улугбек", "фаррух", "шерзод", "шохрух",
        "шахноза", "нилуфар", "фируза", "феруза", "умид", "хуршид", "ботир", "баходир", "азамат", "ислом", "ильхом",
    ]

    /// Surnames without a tell-tale ending (Korean, Chinese, English, Arabic-origin Uzbek).
    static let surnames: Set<String> = [
        "kim", "li", "lee", "pak", "park", "tsoy", "tsoi", "choi", "ten", "khan", "xan", "ni", "shin", "ogay", "tyan",
        "kan", "em", "hegay", "nam", "han", "cho", "jang", "kang",
        "ким", "ли", "пак", "цой", "тен", "хан", "ни", "шин", "огай", "тян", "кан", "эм", "хегай", "нам",
        "wang", "zhang", "liu", "chen", "yang", "huang", "zhao", "zhou",
        // Common English surnames that aren't everyday words (no "Green", "King", "Hill"…: brands use those).
        "smith", "johnson", "williams", "jones", "garcia", "miller", "davis", "rodriguez", "martinez", "wilson",
        "anderson", "taylor", "thomas", "moore", "jackson", "martin", "thompson", "harris", "clark", "lewis",
        "walker", "allen", "wright", "scott", "adams", "nelson", "campbell", "mitchell", "roberts", "phillips",
        "evans", "collins", "edwards", "stewart", "morris", "murphy", "rogers", "peterson",
        "rahim", "karim", "aziz", "said", "salim", "nazar", "ahmad", "ali",
    ]
}
