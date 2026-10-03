import MetlyCapture
import MetlyCore
import MetlyDesign
import SwiftUI

/// "Contact Info" rows: tap to call / mail / open, touch and hold to copy.
struct ContactFieldsSection: View {
    let fields: [ContactField]
    var footer: String?

    var body: some View {
        let visible = fields.filter { !$0.isEmpty }
        if !visible.isEmpty {
            Section {
                ForEach(visible) { field in
                    ContactFieldRow(field: field)
                }
            } header: {
                Text("Contact Info")
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}

struct ContactFieldRow: View {
    let field: ContactField

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
                    Text(field.kind.title)
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
        case .phone: "Calls this number. Touch and hold to copy."
        case .email: "Writes an email. Touch and hold to copy."
        case .telegram: "Opens Telegram. Touch and hold to copy."
        case .website, .linkedin: "Opens the page. Touch and hold to copy."
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
        router.showToast("\(field.kind.title) Copied", systemImage: "doc.on.doc")
    }
}
