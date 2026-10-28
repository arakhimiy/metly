import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Their contact values in their order: phones with their label (Mobile, Work…), email, Telegram, WhatsApp,
/// Instagram, website, LinkedIn. Tap opens the right app, touch and hold copies.
struct ContactInfoSection: View {
    let person: Connection

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        let entries = person.contacts.filter { !$0.isEmpty }
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    if entry.kind == .phone {
                        let phone = entry.labeledPhone
                        PhoneInfoRow(phone: phone, telegramByPhone: telegramByPhone(phone),
                                     onOpen: { openURL($0) }, onCopy: { copy(phone.value) })
                    } else {
                        FieldInfoRow(field: entry.field, url: url(for: entry.field), onOpen: { open(entry.field) },
                                     onCopy: { copy(entry.field) })
                    }
                }
            } header: {
                Text("Contact Info")
            } footer: {
                if PersonReach(person).messagesTelegramByPhone {
                    Text("Message opens Telegram by phone number. Telegram finds them only if their privacy settings allow it.")
                }
            }
        }
    }

    /// Telegram by this number, when no username is saved and Telegram can use it.
    private func telegramByPhone(_ phone: LabeledPhone) -> TelegramTarget? {
        guard ContactLinks.telegramHandle(person.telegram) == nil else { return nil }
        return TelegramPhone.digits(from: phone.value).map(TelegramTarget.phone)
    }

    private func url(for field: ContactField) -> URL? { ContactLinks.url(for: field.kind, value: field.value) }

    private func open(_ field: ContactField) {
        if field.kind == .telegram, let target = TelegramTarget(username: field.value, phones: []) {
            open(target)
        } else if let url = url(for: field) {
            openURL(url)
        }
    }

    private func open(_ target: TelegramTarget) {
        guard let app = target.appURL else { return }
        let web = target.webURL
        openURL(app) { accepted in
            if !accepted, let web { openURL(web) }
        }
    }

    private func copy(_ field: ContactField) {
        UIPasteboard.general.string = field.value
        router.showToast(String(localized: "\(field.kind.title) Copied"), systemImage: "doc.on.doc")
    }

    private func copy(_ phone: String) {
        UIPasteboard.general.string = phone
        router.showToast(String(localized: "\(ContactFieldKind.phone.title) Copied"), systemImage: "doc.on.doc")
    }
}

/// "Mobile  +998 90 123 45 67" — tap calls; the menu copies, texts or opens Telegram by this number.
private struct PhoneInfoRow: View {
    let phone: LabeledPhone
    let telegramByPhone: TelegramTarget?
    let onOpen: (URL) -> Void
    let onCopy: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = ContactLinks.call(phone.value) { onOpen(url) }
        } label: {
            LabeledContent {
                Text(phone.value)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            } label: {
                Label {
                    Text(phone.label.title)
                        .foregroundStyle(.primary)
                } icon: {
                    SettingsIcon(phone.label.symbolName, color: ContactFieldKind.phone.tint)
                }
            }
            .contentShape(.rect)
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
            if let sms = ContactLinks.sms(phone.value) {
                Button("Messages", systemImage: "message") { onOpen(sms) }
            }
            if let telegramByPhone, let app = telegramByPhone.appURL {
                Button {
                    let web = telegramByPhone.webURL
                    openURL(app) { accepted in
                        if !accepted, let web { openURL(web) }
                    }
                } label: {
                    Label {
                        Text("Telegram")
                        Text("Opens the chat by phone number")
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                }
            }
            if let url = ContactLinks.call(phone.value) {
                ShareLink(item: url)
            }
        }
        .accessibilityLabel(Text("\(phone.label.title), \(phone.value)"))
        .accessibilityHint("Calls this number. Touch and hold to copy")
    }
}

/// Email, Telegram, WhatsApp, Instagram, website or LinkedIn — tap opens it.
private struct FieldInfoRow: View {
    let field: ContactField
    let url: URL?
    let onOpen: () -> Void
    let onCopy: () -> Void

    var body: some View {
        Button(action: onOpen) {
            LabeledContent {
                Text(field.value)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
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
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
            if let url {
                ShareLink(item: url)
            }
        }
        .accessibilityHint("Touch and hold to copy")
    }
}
