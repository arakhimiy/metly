import Foundation

/// Columns of the event CSV export, in file order (SPEC §2.5.36 "Included").
enum EventCSVColumn: String, CaseIterable, Identifiable, Sendable {
    case name, jobTitle, company, phone, email, telegram, website, linkedin, event, metAt, place, note, tags, followUp

    var id: String { rawValue }

    /// Header cell of the file — stays English so spreadsheets and CRMs can map the columns.
    var header: String {
        switch self {
        case .name: "Name"
        case .jobTitle: "Title"
        case .company: "Company"
        case .phone: "Phone"
        case .email: "Email"
        case .telegram: "Telegram"
        case .website: "Website"
        case .linkedin: "LinkedIn"
        case .event: "Event"
        case .metAt: "Met At"
        case .place: "Place"
        case .note: "Note"
        case .tags: "Tags"
        case .followUp: "Follow-up"
        }
    }

    /// Toggle title on the export screen.
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .jobTitle: String(localized: "Title", comment: "Job title")
        case .company: String(localized: "Company")
        case .phone: String(localized: "Phone")
        case .email: String(localized: "Email")
        case .telegram: String(localized: "Telegram")
        case .website: String(localized: "Website")
        case .linkedin: String(localized: "LinkedIn")
        case .event: String(localized: "Event")
        case .metAt: String(localized: "Met At", comment: "When you met the person")
        case .place: String(localized: "Place")
        case .note: String(localized: "Note")
        case .tags: String(localized: "Tags")
        case .followUp: String(localized: "Follow-up")
        }
    }

    /// Every export keeps the name so rows stay identifiable.
    var isRequired: Bool { self == .name }

    /// Selected columns in file order.
    static func ordered(_ selection: some Sequence<EventCSVColumn>) -> [EventCSVColumn] {
        let set = Set(selection).union([.name])
        return allCases.filter { set.contains($0) }
    }
}
