import MetlyCapture
import MetlyCore
import MetlyData
import SwiftUI

/// Message · Call · Mail · Save (PLAN Q40: capitalised labels).
/// Message opens Telegram (username, else by phone number — then a menu also offers Messages);
/// Call dials the only number directly, or lists every number ("Mobile · +998…") when there are several.
struct QuickActionsSection: View {
    let person: Connection
    let onSave: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let actions = PersonReach(person)
        Section {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                messageAction(actions)
                callAction(actions)
                QuickActionButton(title: String(localized: "Mail"), systemImage: "envelope.fill",
                                  isEnabled: ContactLinks.mail(person.email) != nil,
                                  accessibilityLabel: String(localized: "Email \(firstName)"), action: mail)
                QuickActionButton(title: String(localized: "Save"), systemImage: "person.crop.circle.badge.plus", isEnabled: true,
                                  accessibilityLabel: String(localized: "Save \(firstName) to Contacts"), action: onSave)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var firstName: String { PersonName.first(person.fullName) }

    // MARK: Message

    @ViewBuilder
    private func messageAction(_ actions: PersonReach) -> some View {
        let title = String(localized: "Message")
        switch actions.message {
        case .telegram(let target) where target.isByPhone && actions.smsURL != nil:
            QuickActionMenu(title: title, systemImage: "message.fill",
                            accessibilityLabel: String(localized: "Message \(firstName)")) {
                Button {
                    openTelegram(target)
                } label: {
                    Label {
                        Text("Telegram")
                        Text("Opens the chat by phone number")
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                }
                if let sms = actions.smsURL {
                    Button("Messages", systemImage: "message") { openURL(sms) }
                }
            }
        case .telegram(let target):
            QuickActionButton(title: title, systemImage: "message.fill", isEnabled: true,
                              accessibilityLabel: String(localized: "Message \(firstName) on Telegram"),
                              accessibilityHint: target.isByPhone ? String(localized: "Opens Telegram by phone number") : nil) {
                openTelegram(target)
            }
        case .sms(let url):
            QuickActionButton(title: title, systemImage: "message.fill", isEnabled: true,
                              accessibilityLabel: String(localized: "Message \(firstName)")) {
                openURL(url)
            }
        case .none:
            QuickActionButton(title: title, systemImage: "message.fill", isEnabled: false,
                              accessibilityLabel: String(localized: "Message \(firstName)")) {}
        }
    }

    /// Telegram app first, then t.me in Safari.
    private func openTelegram(_ target: TelegramTarget) {
        guard let app = target.appURL else { return }
        let web = target.webURL
        openURL(app) { accepted in
            if !accepted, let web { openURL(web) }
        }
    }

    // MARK: Call

    @ViewBuilder
    private func callAction(_ actions: PersonReach) -> some View {
        let title = String(localized: "Call")
        let label = String(localized: "Call \(firstName)")
        if actions.callablePhones.count > 1 {
            QuickActionMenu(title: title, systemImage: "phone.fill", accessibilityLabel: label) {
                ForEach(actions.callablePhones) { phone in
                    Button {
                        call(phone)
                    } label: {
                        Label(phone.labeledValue, systemImage: phone.label.symbolName)
                    }
                }
            }
        } else {
            QuickActionButton(title: title, systemImage: "phone.fill", isEnabled: !actions.callablePhones.isEmpty,
                              accessibilityLabel: label) {
                if let phone = actions.callablePhones.first { call(phone) }
            }
        }
    }

    private func call(_ phone: LabeledPhone) {
        if let url = ContactLinks.call(phone.value) { openURL(url) }
    }

    private func mail() {
        if let url = ContactLinks.mail(person.email) { openURL(url) }
    }
}

/// Bordered tile: icon over a short title.
private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// The same tile opening a menu (several numbers, Telegram or Messages).
private struct QuickActionMenu<Content: View>: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            QuickActionLabel(title: title, systemImage: systemImage)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct QuickActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}
