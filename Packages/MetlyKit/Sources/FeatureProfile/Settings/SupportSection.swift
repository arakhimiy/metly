import MetlyCore
import MetlySharedUI
import StoreKit
import SwiftUI

/// Settings › Support: Rate Nameshake, Contact Support (email), Terms of Use, Privacy Policy and the
/// version. Replaces the old Help & Support screen (no help docs: owner, 2026-11-13).
struct SupportSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var browserPage: BrowserPage?
    private let appInfo = AppInfo.current

    var body: some View {
        Section {
            Button(action: rateApp) {
                SettingsRowLabel("Rate \(Brand.appName)", systemImage: "star.fill", color: .yellow)
            }
            Button(action: contactSupport) {
                LabeledContent {
                    Text(verbatim: Brand.supportEmail)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } label: {
                    SettingsRowLabel("Contact Support", systemImage: "envelope.fill", color: .green)
                }
            }
            Button { browserPage = BrowserPage(url: Brand.termsURL) } label: {
                SettingsRowLabel("Terms of Use", systemImage: "doc.text.fill", color: .gray)
            }
            Button { browserPage = BrowserPage(url: Brand.privacyURL) } label: {
                SettingsRowLabel("Privacy Policy", systemImage: "lock.fill", color: .blue)
            }
        } header: {
            Text("About")
        } footer: {
            Text(verbatim: "\(Brand.appName) \(appInfo.versionDescription)")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .inAppBrowser($browserPage)
    }

    /// The App Store's "Write a Review" page once the app has an App Store ID (`MetlyAppStoreID`);
    /// until then the system rating prompt (which iOS may decline to show).
    private func rateApp() {
        if let url = Brand.writeReviewURL {
            openURL(url)
        } else {
            requestReview()
        }
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
}
