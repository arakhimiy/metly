import CoreGraphics
import Foundation
import MetlyCore
import Testing

/// Realistic OCR output of paper business cards (Vision's raw top-to-bottom order) with the
/// values a person would type in. Layouts the old heuristics got wrong are marked.
struct PaperCardSample: Sendable, CustomTestStringConvertible {
    struct Line: Sendable {
        var text: String
        var height: Double = 0.03
        /// Normalised, top-left origin (only for layouts where geometry matters).
        var frame: CGRect?
    }

    var name: String
    var lines: [Line]
    var fullName = ""
    var jobTitle = ""
    var company = ""
    /// Primary first, then the additional ones.
    var phones: [(String, PhoneLabel)] = []
    var email = ""
    var telegram = ""
    var website = ""

    var testDescription: String { name }
}

extension PaperCardSample.Line: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { text = value }
}

private func line(_ text: String, _ height: Double, _ frame: CGRect? = nil) -> PaperCardSample.Line {
    PaperCardSample.Line(text: text, height: height, frame: frame)
}

private func box(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

enum PaperCardCorpus {
    static let samples: [PaperCardSample] = [
        PaperCardSample(
            name: "Company big at the top, name below (Uzbek)",
            lines: [line("NAJOT TA'LIM", 0.12), line("Jasur Karimov", 0.06), line("O'qituvchi", 0.035),
                    "+998 90 123 45 67", "info@najottalim.uz"],
            fullName: "Jasur Karimov", jobTitle: "O'qituvchi", company: "NAJOT TA'LIM",
            phones: [("+998 90 123 45 67", .mobile)], email: "info@najottalim.uz"),
        PaperCardSample(
            // Old: "Grand Lux" became the name and "Davron Rahim" the company.
            name: "Brand logo in two words above a name the dictionaries don't know",
            lines: [line("GRAND LUX", 0.11), line("Davron Rahim", 0.06), line("Bosh menejer", 0.035),
                    "+998 95 145 67 89", "d.rahim@gmail.com"],
            fullName: "Davron Rahim", jobTitle: "Bosh menejer", company: "GRAND LUX",
            phones: [("+998 95 145 67 89", .mobile)], email: "d.rahim@gmail.com"),
        PaperCardSample(
            // Old: the name went into Company.
            name: "Name and title on one line",
            lines: [line("Aziza Karimova, Product Designer", 0.05), line("TEZKOR", 0.08),
                    "+998 90 123 45 67", "aziza@tezkor.uz"],
            fullName: "Aziza Karimova", jobTitle: "Product Designer", company: "TEZKOR",
            phones: [("+998 90 123 45 67", .mobile)], email: "aziza@tezkor.uz"),
        PaperCardSample(
            name: "Name — CEO, company below",
            lines: [line("Bekzod Aliyev — CEO", 0.05), line("Uzcard", 0.06), "+998 93 000 11 22", "www.uzcard.uz"],
            fullName: "Bekzod Aliyev", jobTitle: "CEO", company: "Uzcard",
            phones: [("+998 93 000 11 22", .mobile)], website: "uzcard.uz"),
        PaperCardSample(
            // Old: the personal domain made the name the company.
            name: "Personal website that contains the surname",
            lines: [line("Jasur Karimov", 0.07), line("Photographer", 0.04), "karimov.uz",
                    "+998 90 555 44 33", "@jasur_photo"],
            fullName: "Jasur Karimov", jobTitle: "Photographer",
            phones: [("+998 90 555 44 33", .mobile)], telegram: "@jasur_photo", website: "karimov.uz"),
        PaperCardSample(
            name: "English: office and mobile numbers",
            lines: [line("Michael Brown", 0.07), line("Senior Consultant", 0.04), line("Deloitte", 0.05),
                    "Office: +1 212 555 0100", "Mobile: +1 917 555 0199", "michael.brown@deloitte.com"],
            fullName: "Michael Brown", jobTitle: "Senior Consultant", company: "Deloitte",
            phones: [("+1 917 555 0199", .mobile), ("+1 212 555 0100", .work)], email: "michael.brown@deloitte.com"),
        PaperCardSample(
            name: "All caps with Tel and Mob",
            lines: [line("AZIZA KARIMOVA", 0.06), line("PRODUCT DESIGNER", 0.04), line("TEZKOR MCHJ", 0.05),
                    "TEL: +998 71 202 02 02", "MOB: +998 90 123 45 67", "AZIZA@TEZKOR.UZ"],
            fullName: "Aziza Karimova", jobTitle: "Product Designer", company: "TEZKOR MCHJ",
            phones: [("+998 90 123 45 67", .mobile), ("+998 71 202 02 02", .work)], email: "aziza@tezkor.uz"),
        PaperCardSample(
            name: "Cyrillic: patronymic, extension, address",
            lines: [line("Иванова Анна Сергеевна", 0.06), line("Руководитель отдела продаж", 0.04),
                    line("АО «Узпромстройбанк»", 0.05), "Тел.: +998 (71) 120-45-00 доб. 210",
                    "Моб.: +998 (90) 350-12-34", "a.ivanova@uzpsb.uz", "г. Ташкент, ул. Шахрисабз, 3"],
            fullName: "Иванова Анна Сергеевна", jobTitle: "Руководитель отдела продаж", company: "АО «Узпромстройбанк»",
            phones: [("+998 90 350 12 34", .mobile), ("+998 71 120 45 00", .work)], email: "a.ivanova@uzpsb.uz"),
        PaperCardSample(
            name: "Cyrillic: bank logo at the top, name below",
            lines: [line("КАПИТАЛБАНК", 0.12), line("Шерзод Алимов", 0.06), line("Главный специалист", 0.035),
                    "Тел: +998 71 200 15 15", "Сот: +998 97 444 55 66", "s.alimov@kapitalbank.uz"],
            fullName: "Шерзод Алимов", jobTitle: "Главный специалист", company: "КАПИТАЛБАНК",
            phones: [("+998 97 444 55 66", .mobile), ("+998 71 200 15 15", .work)], email: "s.alimov@kapitalbank.uz"),
        PaperCardSample(
            name: "Two columns: logo, name and title left, contacts right",
            lines: [
                line("UZUM", 0.10, box(0.06, 0.10, 0.30, 0.10)),
                line("+998 90 555 12 34", 0.03, box(0.58, 0.38, 0.36, 0.03)),
                line("Kamila Yusupova", 0.055, box(0.06, 0.40, 0.42, 0.055)),
                line("+998 71 203 00 00", 0.03, box(0.58, 0.43, 0.36, 0.03)),
                line("Head of Partnerships", 0.035, box(0.06, 0.47, 0.39, 0.035)),
                line("kamila@uzum.com", 0.03, box(0.58, 0.48, 0.34, 0.03)),
                line("uzum.com", 0.03, box(0.58, 0.53, 0.20, 0.03)),
            ],
            fullName: "Kamila Yusupova", jobTitle: "Head of Partnerships", company: "UZUM",
            phones: [("+998 90 555 12 34", .mobile), ("+998 71 203 00 00", .work)],
            email: "kamila@uzum.com", website: "uzum.com"),
        PaperCardSample(
            name: "Logo and tagline above the name; Uzbek Mob and Ish",
            lines: [line("ARTEL", 0.14), line("Home appliances for every family", 0.03), line("Dilnoza Yusupova", 0.06),
                    line("Marketing menejeri", 0.035), "Mob: +998 93 555 12 34", "Ish: +998 71 200 00 00",
                    "d.yusupova@artel.uz"],
            fullName: "Dilnoza Yusupova", jobTitle: "Marketing menejeri", company: "ARTEL",
            phones: [("+998 93 555 12 34", .mobile), ("+998 71 200 00 00", .work)], email: "d.yusupova@artel.uz"),
        PaperCardSample(
            name: "Tagline with a job word; T: and M: labels",
            lines: [line("SILK ROUTE LOGISTICS", 0.10), line("Your trusted partner in Central Asia", 0.03),
                    line("Timur Rashidov", 0.06), line("Operations Director", 0.04),
                    "T: +998 71 150 00 00", "M: +998 99 811 22 33", "timur@silkroute.uz"],
            fullName: "Timur Rashidov", jobTitle: "Operations Director", company: "SILK ROUTE LOGISTICS",
            phones: [("+998 99 811 22 33", .mobile), ("+998 71 150 00 00", .work)], email: "timur@silkroute.uz"),
        PaperCardSample(
            name: "Korean surname first; unlabelled landline and mobile",
            lines: [line("Kim Vladimir", 0.06), line("Director", 0.04), line("Daewoo Textile Fergana", 0.045),
                    "+998 73 244 10 10", "+998 91 650 77 88", "v.kim@dtf.uz"],
            fullName: "Kim Vladimir", jobTitle: "Director", company: "Daewoo Textile Fergana",
            phones: [("+998 91 650 77 88", .mobile), ("+998 73 244 10 10", .work)], email: "v.kim@dtf.uz"),
        PaperCardSample(
            // Old: "Bright Future" became the name and "Chen Wei" the company.
            name: "Two-word brand at the top, short foreign name below",
            lines: [line("Bright Future", 0.09), line("Chen Wei", 0.06), line("Sales Manager", 0.035),
                    "M: +998 99 765 43 21", "chen.wei@mail.ru"],
            fullName: "Chen Wei", jobTitle: "Sales Manager", company: "Bright Future",
            phones: [("+998 99 765 43 21", .mobile)], email: "chen.wei@mail.ru"),
        PaperCardSample(
            name: "Uzbek bank: quoted company, patronymic, local numbers",
            lines: [line("«ORIENT FINANS» XAB", 0.07), line("Rahimova Nigora Akmal qizi", 0.05),
                    line("Kredit bo'limi boshlig'i", 0.035), "Tel: (71) 200-50-50", "Mob: (94) 600-70-80",
                    "n.rahimova@ofb.uz"],
            fullName: "Rahimova Nigora Akmal qizi", jobTitle: "Kredit bo'limi boshlig'i", company: "«ORIENT FINANS» XAB",
            phones: [("(94) 600-70-80", .mobile), ("(71) 200-50-50", .work)], email: "n.rahimova@ofb.uz"),
        PaperCardSample(
            name: "Labels after the numbers; fax skipped",
            lines: [line("Rustam Nazarov", 0.07), "+998 90 123 45 67 (mob.)", "+998 71 234 56 78 (ish)",
                    "+998 71 234 56 79 (faks)", "rustam.nazarov@mail.ru"],
            fullName: "Rustam Nazarov",
            phones: [("+998 90 123 45 67", .mobile), ("+998 71 234 56 78", .work)], email: "rustam.nazarov@mail.ru"),
        PaperCardSample(
            name: "Two labelled numbers on one line",
            lines: [line("Sevara Ismoilova", 0.06), line("HR Manager", 0.04), line("Humo", 0.07),
                    "Tel: +998 71 207 00 00, Mob: +998 90 909 09 09", "sevara@humo.uz"],
            fullName: "Sevara Ismoilova", jobTitle: "HR Manager", company: "Humo",
            phones: [("+998 90 909 09 09", .mobile), ("+998 71 207 00 00", .work)], email: "sevara@humo.uz"),
        PaperCardSample(
            name: "Russian +7 numbers with Раб. and Моб.",
            lines: [line("Петров Алексей", 0.06), line("Технический директор", 0.04), line("ООО «Софт Лаб»", 0.05),
                    "Раб.: +7 (495) 123-45-67", "Моб.: +7 (916) 765-43-21", "petrov@softlab.ru"],
            fullName: "Петров Алексей", jobTitle: "Технический директор", company: "ООО «Софт Лаб»",
            phones: [("+7 (916) 765-43-21", .mobile), ("+7 (495) 123-45-67", .work)], email: "petrov@softlab.ru"),
        PaperCardSample(
            name: "Home number (Uy) and a 33 mobile",
            lines: [line("Malika Saidova", 0.06), line("Tarjimon", 0.04), "Uy: +998 71 255 33 44", "Mob: +998 33 123 45 67"],
            fullName: "Malika Saidova", jobTitle: "Tarjimon",
            phones: [("+998 33 123 45 67", .mobile), ("+998 71 255 33 44", .home)]),
        PaperCardSample(
            name: "All caps: company logo at the top, name and title below",
            lines: [line("AKFA GROUP", 0.10), line("SARDOR TOSHMATOV", 0.06), line("BOSH DIREKTOR O'RINBOSARI", 0.035),
                    "+998 78 113 00 00", "+998 97 700 00 01", "www.akfagroup.com"],
            fullName: "Sardor Toshmatov", jobTitle: "Bosh Direktor O'rinbosari", company: "AKFA GROUP",
            phones: [("+998 97 700 00 01", .mobile), ("+998 78 113 00 00", .work)], website: "akfagroup.com"),
        PaperCardSample(
            name: "Company line equal to the email domain",
            lines: [line("Najot Nur", 0.08), line("Gulshan Ergasheva", 0.06), line("Bosh hisobchi", 0.035),
                    "+998 90 777 66 55", "info@najotnur.uz"],
            fullName: "Gulshan Ergasheva", jobTitle: "Bosh hisobchi", company: "Najot Nur",
            phones: [("+998 90 777 66 55", .mobile)], email: "info@najotnur.uz"),
        PaperCardSample(
            name: "Uzbek logo and slogan with a job word",
            lines: [line("ZAMIN", 0.12), line("Qurilishda ishonchli hamkor", 0.03), line("Ulug'bek Qodirov", 0.06),
                    line("Loyiha rahbari", 0.035), "+998 99 300 40 50", "zamin.uz"],
            fullName: "Ulug'bek Qodirov", jobTitle: "Loyiha rahbari", company: "ZAMIN",
            phones: [("+998 99 300 40 50", .mobile)], website: "zamin.uz"),
        PaperCardSample(
            name: "Cyrillic all caps name, quoted company first, unlabelled numbers",
            lines: [line("ООО «АРТ ДИЗАЙН»", 0.05), line("ЮЛИЯ ПАК", 0.07), line("Арт-директор", 0.04),
                    "+998 90 188 88 88", "+998 71 233 33 33", "info@artdesign.uz"],
            fullName: "Юлия Пак", jobTitle: "Арт-директор", company: "ООО «АРТ ДИЗАЙН»",
            phones: [("+998 90 188 88 88", .mobile), ("+998 71 233 33 33", .work)], email: "info@artdesign.uz"),
        PaperCardSample(
            name: "Name in the middle, big brand on the right (two columns)",
            lines: [
                line("Nodira Azimova", 0.06, box(0.06, 0.12, 0.44, 0.06)),
                line("EPAM", 0.12, box(0.66, 0.10, 0.26, 0.12)),
                line("Lead Software Engineer", 0.035, box(0.06, 0.20, 0.48, 0.035)),
                line("+998 90 321 00 99", 0.03, box(0.06, 0.70, 0.36, 0.03)),
                line("nodira_azimova@epam.com", 0.03, box(0.06, 0.75, 0.48, 0.03)),
            ],
            fullName: "Nodira Azimova", jobTitle: "Lead Software Engineer", company: "EPAM",
            phones: [("+998 90 321 00 99", .mobile)], email: "nodira_azimova@epam.com"),
        PaperCardSample(
            name: "Big name at the top, company small at the bottom",
            lines: [line("Bahodir Yusupov", 0.09), line("Founder", 0.04), "+998 88 200 30 40", "t.me/bahodir_y",
                    line("Mohir Soft", 0.03)],
            fullName: "Bahodir Yusupov", jobTitle: "Founder", company: "Mohir Soft",
            phones: [("+998 88 200 30 40", .mobile)], telegram: "@bahodir_y"),
    ]
}
