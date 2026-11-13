import MetlyCore
import StoreKit
import MetlySharedUI
import SwiftUI

/// SETTINGS_HELP (SPEC §2.5.20).
struct HelpSupportScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var browserPage: BrowserPage?
    private let appInfo = AppInfo.current

    var body: some View {
        Form {
            Section("Help") {
                Button(action: openHelpCenter) {
                    SettingsRowLabel("Help Center", systemImage: "book.fill", color: .blue)
                }
                Button(action: contactSupport) {
                    LabeledContent {
                        Text(Brand.supportEmail)
                            .foregroundStyle(Color.secondary)
                    } label: {
                        SettingsRowLabel("Contact Support", systemImage: "envelope.fill", color: .green)
                    }
                }
            }

            Section {
                Button(action: rateApp) {
                    SettingsRowLabel("Rate \(Brand.appName)", systemImage: "star.fill", color: .yellow)
                }
                Button(action: openTerms) {
                    SettingsRowLabel("Terms of Use", systemImage: "doc.text.fill", color: .gray)
                }
                Button(action: openPrivacyPolicy) {
                    SettingsRowLabel("Privacy Policy", systemImage: "hand.raised.fill", color: .blue)
                }
            } header: {
                Text("About")
            } footer: {
                Text("\(Brand.appName) \(appInfo.versionDescription)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
        .inAppBrowser($browserPage)
    }

    private func openHelpCenter() {
        browserPage = BrowserPage(url: Brand.helpURL)
    }

    private func openTerms() {
        browserPage = BrowserPage(url: Brand.termsURL)
    }

    private func openPrivacyPolicy() {
        browserPage = BrowserPage(url: Brand.privacyURL)
    }

    /// Opens Mail with version + device prefilled; without a mail app, copies the address instead.
    private func contactSupport() {
        guard let url = SupportMail.url(appInfo: appInfo) else { return }
        let router = router
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = Brand.supportEmail
            router.showToast(String(localized: "Email Address Copied", bundle: .appStrings), systemImage: "doc.on.doc")
        }
    }

    /// TODO: once the App Store ID exists, open `https://apps.apple.com/app/id<ID>?action=write-review`
    /// (the system may decline to show the review prompt).
    private func rateApp() {
        requestReview()
    }
}

#Preview("Help & Support") {
    NavigationStack { HelpSupportScreen() }
        .metlyPreview(.full)
}
