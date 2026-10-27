import MetlyCapture
import MetlyCore
import MetlyData
import SwiftUI

/// Message · Call · Mail · Save (PLAN Q40: capitalised labels).
struct QuickActionsSection: View {
    let person: Connection
    let onSave: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                QuickActionButton(title: String(localized: "Message"), systemImage: "message.fill", isEnabled: canMessage,
                                  accessibilityLabel: messageLabel, action: message)
                QuickActionButton(title: String(localized: "Call"), systemImage: "phone.fill",
                                  isEnabled: ContactLinks.call(person.phone) != nil,
                                  accessibilityLabel: String(localized: "Call \(firstName)"), action: call)
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

    private var canMessage: Bool {
        ContactLinks.telegramApp(person.telegram) != nil || ContactLinks.sms(person.phone) != nil
    }

    private var messageLabel: String {
        ContactLinks.telegramHandle(person.telegram) != nil
            ? String(localized: "Message \(firstName) on Telegram") : String(localized: "Message \(firstName)")
    }

    /// Telegram first (app, then t.me in Safari), otherwise Messages.
    private func message() {
        if let app = ContactLinks.telegramApp(person.telegram) {
            let web = ContactLinks.telegramWeb(person.telegram)
            openURL(app) { accepted in
                if !accepted, let web { openURL(web) }
            }
        } else if let sms = ContactLinks.sms(person.phone) {
            openURL(sms)
        }
    }

    private func call() {
        if let url = ContactLinks.call(person.phone) { openURL(url) }
    }

    private func mail() {
        if let url = ContactLinks.mail(person.email) { openURL(url) }
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
