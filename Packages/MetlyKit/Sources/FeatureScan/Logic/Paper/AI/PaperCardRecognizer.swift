import Foundation
import MetlyCore

/// OCR lines → `PaperScan`: heuristics always, plus the on-device model when there is one.
///
/// With a model (iOS 26+, Apple Intelligence on): its validated name / title / company are pinned
/// and the heuristics fill whatever it left out (per field — nothing is all-or-nothing). Contact
/// values come from the pattern matchers first, which read them exactly; the model only adds ones
/// they missed and labels numbers the card didn't label.
nonisolated enum PaperCardRecognizer {
    static let modelTimeout: Duration = .seconds(4)

    static func recognize(_ lines: [OCRLine], model: (any PaperCardLanguageModel)?,
                          timeout: Duration = modelTimeout) async -> PaperScan {
        let analysis = PaperCardParser.analyze(lines)
        guard let model, !analysis.segments.isEmpty else { return analysis.scan }
        let prompt = PaperModelPrompt.text(for: analysis.lines)
        guard let output = await PaperModelRunner.run(model, prompt: prompt, timeout: timeout) else { return analysis.scan }
        return merge(PaperModelValidator.validate(output, against: analysis), into: analysis)
    }

    /// Combines a validated model answer with the heuristic reading.
    static func merge(_ model: PaperModelOutput, into analysis: PaperAnalysis) -> PaperScan {
        guard !model.isEmpty else { return analysis.scan }
        let heuristic = analysis.roles

        // Roles: the model's are pinned; the heuristics search the remaining lines for the rest.
        let pinned = PaperRoles(name: model.fullName, title: model.jobTitle, company: model.company)
        var roles = PaperRoleClassifier.classify(analysis.candidates, context: analysis.context, pinned: pinned)
        // Sure when both readers agree, or when only the heuristics answered and they were sure.
        roles.confident = Set(PaperRoles.fields.filter { field in
            let modelValue = pinned[field]
            if modelValue.isEmpty { return heuristic.confident.contains(field) && roles[field] == heuristic[field] }
            return same(modelValue, heuristic[field])
        })

        var contacts = analysis.contacts
        for phone in model.phones {
            if let index = contacts.phones.firstIndex(where: { PhoneFormat.key($0.value) == PhoneFormat.key(phone.number) }) {
                // The card printed no label and the prefix didn't tell: take the model's reading.
                if !contacts.phones[index].isLabelled, PhoneFormat.inferredLabel(phone.number) == nil, let label = phone.label {
                    contacts.phones[index].label = label
                }
            } else {
                contacts.add(PaperContacts.Phone(value: phone.number,
                                                 label: phone.label ?? PhoneFormat.inferredLabel(phone.number) ?? .mobile,
                                                 isLabelled: false))
            }
        }
        if contacts.emails.isEmpty, !model.email.isEmpty { contacts.emails = [model.email] }
        if contacts.telegrams.isEmpty, !model.telegram.isEmpty, let username = model.telegram.split(separator: "@").last {
            contacts.telegrams = [String(username)]
        }
        if contacts.websites.isEmpty, !model.website.isEmpty { contacts.websites = [model.website] }
        if contacts.linkedins.isEmpty, !model.linkedin.isEmpty { contacts.linkedins = [model.linkedin] }

        return PaperScan(draft: PaperCardParser.draft(roles: roles, contacts: contacts), recognizedText: analysis.segments,
                         confidentFields: roles.confident)
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        !lhs.isEmpty && PaperText.comparable(lhs) == PaperText.comparable(rhs)
    }
}
