import CoreGraphics
import Foundation
import MetlyCore

/// Cards written after the heuristics were tuned on `PaperCardCorpus` and never tuned against —
/// an honest measure of how the reader does on layouts it hasn't seen.
enum PaperHoldoutCorpus {
    private static func line(_ text: String, _ height: Double = 0.03, _ frame: CGRect? = nil) -> PaperCardSample.Line {
        PaperCardSample.Line(text: text, height: height, frame: frame)
    }

    static let samples: [PaperCardSample] = [
        PaperCardSample(
            name: "Uzbek bank, long Uzbek title",
            lines: [line("«IPAK YO‘LI» BANKI", 0.08), line("Shoira Mirzayeva", 0.06),
                    line("Mijozlar bilan ishlash bo‘yicha mutaxassis", 0.03), "Tel.: +998 71 140 33 33",
                    "Mob.: +998 90 920 11 22", "sh.mirzayeva@ipakyulibank.uz", "www.ipakyulibank.uz"],
            fullName: "Shoira Mirzayeva", jobTitle: "Mijozlar bilan ishlash bo‘yicha mutaxassis", company: "«IPAK YO‘LI» BANKI",
            phones: [("+998 90 920 11 22", .mobile), ("+998 71 140 33 33", .work)],
            email: "sh.mirzayeva@ipakyulibank.uz", website: "ipakyulibank.uz"),
        PaperCardSample(
            name: "English startup, Co-founder & CTO",
            lines: [line("Lena Park", 0.07), line("Co-founder & CTO", 0.04), line("Brightloop", 0.05),
                    "lena@brightloop.io", "+1 650 555 0142", "brightloop.io"],
            fullName: "Lena Park", jobTitle: "Co-founder & CTO", company: "Brightloop",
            phones: [("+1 650 555 0142", .mobile)], email: "lena@brightloop.io", website: "brightloop.io"),
        PaperCardSample(
            name: "Latin brand at the top, Cyrillic name",
            lines: [line("Uzum Bank", 0.10), line("Ахмедов Тимур Рустамович", 0.05), line("Руководитель направления", 0.035),
                    "+998 78 777 77 77", "+998 90 111 23 45", "t.ahmedov@uzumbank.uz"],
            fullName: "Ахмедов Тимур Рустамович", jobTitle: "Руководитель направления", company: "Uzum Bank",
            phones: [("+998 90 111 23 45", .mobile), ("+998 78 777 77 77", .work)], email: "t.ahmedov@uzumbank.uz"),
        PaperCardSample(
            name: "Hotel brand with a city in it",
            lines: [line("HYATT REGENCY TASHKENT", 0.07), line("Gulnoza Saidova", 0.06), line("Sales Manager", 0.035),
                    "T +998 71 207 12 34", "M +998 93 380 00 11", "gulnoza.saidova@hyatt.com"],
            fullName: "Gulnoza Saidova", jobTitle: "Sales Manager", company: "HYATT REGENCY TASHKENT",
            phones: [("+998 93 380 00 11", .mobile), ("+998 71 207 12 34", .work)], email: "gulnoza.saidova@hyatt.com"),
        PaperCardSample(
            name: "University: lower-case institution name, title above the name",
            lines: [line("Toshkent davlat iqtisodiyot universiteti", 0.04), line("Dotsent", 0.035),
                    line("Karimov Bahrom Ergashevich", 0.06), "+998 71 239 28 48", "b.karimov@tsue.uz"],
            fullName: "Karimov Bahrom Ergashevich", jobTitle: "Dotsent", company: "Toshkent davlat iqtisodiyot universiteti",
            phones: [("+998 71 239 28 48", .work)], email: "b.karimov@tsue.uz"),
        PaperCardSample(
            name: "Freelancer in capitals, portfolio link",
            lines: [line("AKMAL TURSUNOV", 0.07), line("UX/UI DESIGNER", 0.04), "+998 97 123 45 67", "@akmal_design",
                    "behance.net/akmaltursunov"],
            fullName: "Akmal Tursunov", jobTitle: "UX/UI Designer",
            phones: [("+998 97 123 45 67", .mobile)], telegram: "@akmal_design", website: "behance.net/akmaltursunov"),
        PaperCardSample(
            name: "Brand with digits and a slogan with digits",
            lines: [line("Express24", 0.10), line("Delivery in 30 minutes", 0.03), line("Otabek Nazarov", 0.06),
                    line("Operations Manager", 0.035), "+998 71 200 24 24", "Mob: +998 99 024 24 24", "otabek@express24.uz"],
            fullName: "Otabek Nazarov", jobTitle: "Operations Manager", company: "Express24",
            phones: [("+998 99 024 24 24", .mobile), ("+998 71 200 24 24", .work)], email: "otabek@express24.uz"),
        PaperCardSample(
            name: "Doctor: Dr. prefix, unknown job word",
            lines: [line("Dr. Malika Yusupova", 0.06), line("Kardiolog", 0.04), line("MedLine Clinic", 0.05),
                    "+998 90 555 03 03", "info@medline.uz"],
            fullName: "Dr. Malika Yusupova", jobTitle: "Kardiolog", company: "MedLine Clinic",
            phones: [("+998 90 555 03 03", .mobile)], email: "info@medline.uz"),
        PaperCardSample(
            name: "Two columns: name and title left, logo and contacts right",
            lines: [
                line("NAVBAHOR", 0.10, CGRect(x: 0.62, y: 0.10, width: 0.30, height: 0.10)),
                line("Sherzod Aliyev", 0.07, CGRect(x: 0.06, y: 0.30, width: 0.45, height: 0.07)),
                line("Head of Marketing", 0.04, CGRect(x: 0.06, y: 0.39, width: 0.40, height: 0.04)),
                line("+998 90 100 20 30", 0.03, CGRect(x: 0.58, y: 0.55, width: 0.36, height: 0.03)),
                line("+998 71 150 60 70", 0.03, CGRect(x: 0.58, y: 0.62, width: 0.36, height: 0.03)),
                line("s.aliyev@navbahor.uz", 0.03, CGRect(x: 0.58, y: 0.69, width: 0.38, height: 0.03)),
            ],
            fullName: "Sherzod Aliyev", jobTitle: "Head of Marketing", company: "NAVBAHOR",
            phones: [("+998 90 100 20 30", .mobile), ("+998 71 150 60 70", .work)], email: "s.aliyev@navbahor.uz"),
        PaperCardSample(
            name: "US law firm: initial, Direct and Cell",
            lines: [line("J. Robert Miller", 0.06), line("Managing Partner", 0.04), line("Miller & Co. Law Firm", 0.05),
                    "Direct: +1 212 555 0177", "Cell: +1 646 555 0123", "jmiller@millerlaw.com"],
            fullName: "J. Robert Miller", jobTitle: "Managing Partner", company: "Miller & Co. Law Firm",
            phones: [("+1 646 555 0123", .mobile), ("+1 212 555 0177", .work)], email: "jmiller@millerlaw.com"),
        PaperCardSample(
            name: "Uzbek Cyrillic: bank first, patronymic",
            lines: [line("АТБ «Ўзсаноатқурилишбанк»", 0.06), line("Абдуллаев Жасур Тохирович", 0.05),
                    line("Бўлим бошлиғи", 0.035), "Тел: +998 71 120 45 45", "Моб: +998 90 977 88 99"],
            fullName: "Абдуллаев Жасур Тохирович", jobTitle: "Бўлим бошлиғи", company: "АТБ «Ўзсаноатқурилишбанк»",
            phones: [("+998 90 977 88 99", .mobile), ("+998 71 120 45 45", .work)]),
        PaperCardSample(
            name: "Company between name and title",
            lines: [line("Laziz Abdullayev", 0.06), line("PAYME", 0.07), line("Senior Backend Developer", 0.035),
                    "+998 99 811 00 00", "laziz@payme.uz"],
            fullName: "Laziz Abdullayev", jobTitle: "Senior Backend Developer", company: "PAYME",
            phones: [("+998 99 811 00 00", .mobile)], email: "laziz@payme.uz"),
        PaperCardSample(
            name: "Name | Title on one line",
            lines: [line("Diyora Karimova | Brand Manager", 0.05), line("Korzinka", 0.07), "+998 90 400 55 66",
                    "diyora.k@korzinka.uz"],
            fullName: "Diyora Karimova", jobTitle: "Brand Manager", company: "Korzinka",
            phones: [("+998 90 400 55 66", .mobile)], email: "diyora.k@korzinka.uz"),
        PaperCardSample(
            name: "Odd phone formats",
            lines: [line("Nodir Qodirov", 0.06), line("Bosh muhandis", 0.04), line("UzAuto Motors", 0.05),
                    "тел.: (+998 71) 200-11-22", "моб.: +998(93)1234567"],
            fullName: "Nodir Qodirov", jobTitle: "Bosh muhandis", company: "UzAuto Motors",
            phones: [("+998 93 123 45 67", .mobile), ("+998 71 200 11 22", .work)]),
        PaperCardSample(
            name: "Cyrillic brand equal to the website",
            lines: [line("Корзинка", 0.10), line("Мадина Рахимова", 0.06), line("Директор по маркетингу", 0.035),
                    "+998 78 140 10 10", "korzinka.uz"],
            fullName: "Мадина Рахимова", jobTitle: "Директор по маркетингу", company: "Корзинка",
            phones: [("+998 78 140 10 10", .work)], website: "korzinka.uz"),
    ]
}
