import Foundation
import MetlyCore
import Testing
@testable import FeatureScan

/// Stands in for Foundation Models: streams `partials`, then answers, fails or never finishes.
private struct MockCardModel: PaperCardLanguageModel {
    var partials: [PaperModelOutput] = []
    var answer = PaperModelOutput()
    var error: (any Error)?
    var hangs = false

    @concurrent func prepare() async {}

    @concurrent func read(_ prompt: String, partial: @escaping @Sendable (PaperModelOutput) -> Void) async throws -> PaperModelOutput {
        for snapshot in partials { partial(snapshot) }
        if hangs { try await Task.sleep(for: .seconds(30)) }
        if let error { throw error }
        return answer
    }
}

private struct Refusal: Error {}

@Suite("On-device model: validation, merge, time box")
struct PaperModelTests {
    private let jasurCard = [
        OCRLine("NAJOT TA'LIM", height: 0.12), OCRLine("Jasur Karimov", height: 0.06), OCRLine("O'qituvchi", height: 0.035),
        OCRLine("+998 90 123 45 67"), OCRLine("info@najottalim.uz"),
    ]

    private func phone(_ draft: PaperCardDraft) -> String {
        draft.fields.first { $0.kind == .phone }?.value ?? ""
    }

    // MARK: Validation

    @Test("Values present on the card survive, as printed (case and spacing from the OCR)")
    func keepsPresentValues() {
        let analysis = PaperCardParser.analyze(jasurCard)
        let output = PaperModelOutput(fullName: "jasur  karimov", jobTitle: "O‘qituvchi", company: "Najot Ta'lim",
                                      phones: [.init(number: "+998901234567", label: .mobile)], email: "INFO@najottalim.uz")
        let valid = PaperModelValidator.validate(output, against: analysis)
        #expect(valid.fullName == "Jasur Karimov")
        #expect(valid.jobTitle == "O'qituvchi")
        #expect(valid.company == "NAJOT TA'LIM")
        #expect(valid.phones == [.init(number: "+998 90 123 45 67", label: .mobile)])
        #expect(valid.email == "info@najottalim.uz")
    }

    @Test("Invented values are dropped")
    func dropsInventions() {
        let analysis = PaperCardParser.analyze(jasurCard)
        let output = PaperModelOutput(fullName: "John Doe", jobTitle: "Chief Executive Officer", company: "Najot Education LLC",
                                      phones: [.init(number: "+998 99 000 00 00", label: .work),
                                               .init(number: "info@najottalim.uz", label: .other)],
                                      email: "jasur@najottalim.uz", telegram: "@jasur", website: "najottalim.com",
                                      linkedin: "in/jasurkarimov")
        #expect(PaperModelValidator.validate(output, against: analysis) == PaperModelOutput())
    }

    @Test("A transliterated answer maps back to the Cyrillic text on the card")
    func transliteration() {
        let analysis = PaperCardParser.analyze(text: ["Иванова Анна Сергеевна", "Руководитель отдела продаж", "АО «Узпромстройбанк»"])
        let output = PaperModelOutput(fullName: "Ivanova Anna Sergeevna", company: "AO Uzpromstroybank")
        let valid = PaperModelValidator.validate(output, against: analysis)
        #expect(valid.fullName == "Иванова Анна Сергеевна")
        #expect(valid.company == "АО «Узпромстройбанк»")
    }

    @Test("Sanity checks: a legal entity isn't a name, a person isn't a company, no role twice")
    func sanity() {
        let analysis = PaperCardParser.analyze(text: ["TEZKOR MCHJ", "Aziza Karimova", "Product Designer", "aziza@tezkor.uz"])
        let swapped = PaperModelValidator.validate(PaperModelOutput(fullName: "TEZKOR MCHJ", company: "Aziza Karimova"),
                                                   against: analysis)
        #expect(swapped.fullName.isEmpty)
        #expect(swapped.company.isEmpty)
        let twice = PaperModelValidator.validate(PaperModelOutput(fullName: "Aziza Karimova", jobTitle: "Aziza Karimova"),
                                                 against: analysis)
        #expect(twice.fullName == "Aziza Karimova")
        #expect(twice.jobTitle.isEmpty)
    }

    @Test("Fuzzy span matching", arguments: [
        ("Jasur Karimov", "Jasur Karimov"),
        ("Jasur Karimow", "Jasur Karimov"),
        ("JASUR KARIMOV", "Jasur Karimov"),
        ("Karimov", "Karimov"),
    ])
    func span(value: String, expected: String) {
        #expect(PaperModelValidator.span(matching: value, in: ["Jasur Karimov", "+998 90 123 45 67"]) == expected)
    }

    @Test("Short values must match exactly")
    func shortSpan() {
        #expect(PaperModelValidator.span(matching: "Uzum", in: ["UZUM"]) == "UZUM")
        #expect(PaperModelValidator.span(matching: "Uzim", in: ["UZUM"]) == nil)
    }

    // MARK: Merge

    @Test("The model settles an ambiguous layout; the heuristics fill what it left out")
    func mergeFixesLayout() {
        let lines = [OCRLine("Bobo Tosh", height: 0.09), OCRLine("Grand Lux", height: 0.06), OCRLine("Bosh menejer", height: 0.035),
                     OCRLine("+998 95 145 67 89")]
        let analysis = PaperCardParser.analyze(lines)
        #expect(analysis.roles.name == "Grand Lux")  // the heuristics alone get this one wrong

        let scan = PaperCardRecognizer.merge(PaperModelValidator.validate(
            PaperModelOutput(fullName: "Bobo Tosh", company: "Grand Lux"), against: analysis), into: analysis)
        #expect(scan.draft.fullName == "Bobo Tosh")
        #expect(scan.draft.company == "Grand Lux")
        #expect(scan.draft.jobTitle == "Bosh menejer")
        #expect(phone(scan.draft) == "+998 95 145 67 89")
        #expect(!scan.confidentFields.contains(.name))  // the two readers disagreed
    }

    @Test("Per-field fallback: an invalid name is replaced by the heuristics, a valid company kept")
    func perFieldFallback() async {
        let model = MockCardModel(answer: PaperModelOutput(fullName: "Jasur Karimov Bekovich", company: "NAJOT TA'LIM"))
        let scan = await PaperCardRecognizer.recognize(jasurCard, model: model)
        #expect(scan.draft.fullName == "Jasur Karimov")
        #expect(scan.draft.company == "NAJOT TA'LIM")
        #expect(scan.draft.jobTitle == "O'qituvchi")
        #expect(scan.confidentFields.contains(.company))
    }

    @Test("Agreement makes a role confident")
    func agreement() async {
        let model = MockCardModel(answer: PaperModelOutput(fullName: "Jasur Karimov", jobTitle: "O'qituvchi", company: "NAJOT TA'LIM"))
        let scan = await PaperCardRecognizer.recognize(jasurCard, model: model)
        #expect(scan.confidentFields == [.name, .title, .company])
    }

    @Test("Phones: the card's numbers stay; the model labels an unlabelled foreign number and adds a missed one")
    func mergePhones() {
        let analysis = PaperCardParser.analyze(text: ["Chen Wei", "+1 415 555 0123", "Mob: +998 99 765 43 21"])
        let output = PaperModelOutput(phones: [.init(number: "+1 415 555 0123", label: .work),
                                               .init(number: "+998 99 765 43 21", label: .home)])
        let scan = PaperCardRecognizer.merge(PaperModelValidator.validate(output, against: analysis), into: analysis)
        #expect(phone(scan.draft) == "+998 99 765 43 21")
        #expect(scan.draft.phoneLabel == .mobile)  // printed "Mob" beats the model
        #expect(scan.draft.additionalPhones.first { $0.value == "+1 415 555 0123" }?.label == .work)
    }

    // MARK: Time box & errors

    @Test("Errors and refusals fall back to the heuristics")
    func errorFallsBack() async {
        let scan = await PaperCardRecognizer.recognize(jasurCard, model: MockCardModel(error: Refusal()))
        #expect(scan == PaperCardParser.analyze(jasurCard).scan)
    }

    @Test("No model: heuristics only")
    func noModel() async {
        #expect(await PaperCardRecognizer.recognize(jasurCard, model: nil) == PaperCardParser.analyze(jasurCard).scan)
    }

    @Test("A model that doesn't finish in time doesn't hold the scan up; finished fields are used")
    func timeBox() async {
        let model = MockCardModel(partials: [PaperModelOutput(fullName: "Jasur Karimov")], hangs: true)
        let clock = ContinuousClock()
        let start = clock.now
        let output = await PaperModelRunner.run(model, prompt: "", timeout: .milliseconds(200))
        #expect(clock.now - start < .seconds(5))
        #expect(output == PaperModelOutput(fullName: "Jasur Karimov"))
    }

    @Test("A finished answer wins over the partial ones")
    func answered() async {
        let model = MockCardModel(partials: [PaperModelOutput(fullName: "Jasur")],
                                  answer: PaperModelOutput(fullName: "Jasur Karimov", company: "NAJOT TA'LIM"))
        let output = await PaperModelRunner.run(model, prompt: "", timeout: .seconds(4))
        #expect(output == PaperModelOutput(fullName: "Jasur Karimov", company: "NAJOT TA'LIM"))
    }

    // MARK: Prompt

    @Test("The prompt frames each line with its size and position, in English")
    func prompt() {
        let text = PaperModelPrompt.text(for: [
            OCRLine("NAJOT TA'LIM", frame: CGRect(x: 0.05, y: 0.05, width: 0.3, height: 0.12)),
            OCRLine("Jasur Karimov", frame: CGRect(x: 0.4, y: 0.45, width: 0.3, height: 0.06)),
            OCRLine("+998 90 123 45 67", frame: CGRect(x: 0.65, y: 0.8, width: 0.3, height: 0.03)),
        ])
        #expect(text.contains("Line 1 (largest text, top left): NAJOT TA'LIM"))
        #expect(text.contains("Line 2 (medium text, middle): Jasur Karimov"))
        #expect(text.contains("Line 3 (small text, bottom right): +998 90 123 45 67"))
        #expect(!PaperModelPrompt.instructions.contains("Jasur"))
    }
}
