import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Their contact values; tap opens the right app, touch and hold copies.
struct ContactInfoSection: View {
    let person: Connection

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        let fields = person.availableFields
        if !fields.isEmpty {
            Section("Contact Info") {
                ForEach(fields) { field in
                    Button {
                        open(field)
                    } label: {
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
                        Button("Copy", systemImage: "doc.on.doc") { copy(field) }
                        if let url = url(for: field) {
                            ShareLink(item: url)
                        }
                    }
                    .accessibilityHint("Touch and hold to copy")
                }
            }
        }
    }

    private func url(for field: ContactField) -> URL? {
        switch field.kind {
        case .phone: ContactLinks.call(field.value)
        case .email: ContactLinks.mail(field.value)
        case .telegram: ContactLinks.telegramWeb(field.value)
        case .website: ContactLinks.website(field.value)
        case .linkedin: ContactLinks.linkedIn(field.value)
        }
    }

    private func open(_ field: ContactField) {
        if field.kind == .telegram, let app = ContactLinks.telegramApp(field.value) {
            let web = ContactLinks.telegramWeb(field.value)
            openURL(app) { accepted in
                if !accepted, let web { openURL(web) }
            }
        } else if let url = url(for: field) {
            openURL(url)
        }
    }

    private func copy(_ field: ContactField) {
        UIPasteboard.general.string = field.value
        router.showToast(String(localized: "\(field.kind.title) Copied"), systemImage: "doc.on.doc")
    }
}
