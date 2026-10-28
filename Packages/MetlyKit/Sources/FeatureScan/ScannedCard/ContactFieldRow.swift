import MetlyCapture
import MetlyCore
import MetlyDesign
import SwiftUI

/// "Contact Info" rows: tap to call / mail / open, touch and hold to copy. When a contact has more
/// than one number (a vCard's TEL;TYPE=CELL / WORK…), each phone row shows its label.
struct ContactFieldsSection: View {
    let fields: [ContactField]
    var phoneLabel: PhoneLabel = .mobile
    var additionalPhones: [LabeledPhone] = []
    var footer: String?

    var body: some View {
        let rows = self.rows
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.id) { row in
                    ContactFieldRow(field: row.field, title: row.title)
                }
            } header: {
                Text("Contact Info")
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    /// Non-empty fields in order, the extra phones right after the main one (or first without one).
    private var rows: [(id: String, field: ContactField, title: String?)] {
        let extra = additionalPhones.filter { !$0.isEmpty }
        let extraRows = extra.map { (id: $0.id.uuidString, field: ContactField(kind: .phone, value: $0.value), title: Optional($0.label.title)) }
        var rows: [(id: String, field: ContactField, title: String?)] = []
        var placedExtra = false
        for field in fields where !field.isEmpty {
            if field.kind == .phone {
                rows.append((field.kind.rawValue, field, extra.isEmpty ? nil : phoneLabel.title))
                rows += extraRows
                placedExtra = true
            } else {
                rows.append((field.kind.rawValue, field, nil))
            }
        }
        return placedExtra ? rows : extraRows + rows
    }
}

struct ContactFieldRow: View {
    let field: ContactField
    /// Replaces the kind's name ("Mobile", "Work" for labelled phones).
    var title: String?

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: open) {
            LabeledContent {
                Text(field.value)
                    .foregroundStyle(.tint)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label {
                    Text(title ?? field.kind.title)
                        .foregroundStyle(.primary)
                } icon: {
                    SettingsIcon(field: field.kind)
                }
            }
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            if let url {
                ShareLink(item: url)
            }
        }
        .accessibilityHint(hint)
    }

    private var url: URL? {
        switch field.kind {
        case .phone: ContactLinks.call(field.value)
        case .email: ContactLinks.mail(field.value)
        case .telegram: ContactLinks.telegramWeb(field.value)
        case .website: ContactLinks.website(field.value)
        case .linkedin: ContactLinks.linkedIn(field.value)
        }
    }

    private var hint: String {
        switch field.kind {
        case .phone: String(localized: "Calls this number. Touch and hold to copy.")
        case .email: String(localized: "Writes an email. Touch and hold to copy.")
        case .telegram: String(localized: "Opens Telegram. Touch and hold to copy.")
        case .website, .linkedin: String(localized: "Opens the page. Touch and hold to copy.")
        }
    }

    private func open() {
        if field.kind == .telegram, let app = ContactLinks.telegramApp(field.value) {
            let web = ContactLinks.telegramWeb(field.value)
            openURL(app) { accepted in
                if !accepted, let web { openURL(web) }
            }
        } else if let url {
            openURL(url)
        }
    }

    private func copy() {
        UIPasteboard.general.string = field.value
        router.showToast(String(localized: "\(field.kind.title) Copied"), systemImage: "doc.on.doc")
    }
}
