import Foundation
import MetlyCore
import SwiftUI

/// "By continuing you agree to the Terms and Privacy Policy." with tappable links.
struct LegalFooter: View {
    var body: some View {
        Text(Self.attributedText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .tint(.accentColor)
    }

    static var attributedText: AttributedString {
        var terms = AttributedString(localized: "Terms")
        terms.link = Brand.termsURL
        var privacy = AttributedString(localized: "Privacy Policy")
        privacy.link = Brand.privacyURL

        var text = AttributedString(localized: "By continuing you agree to the ")
        text.append(terms)
        text.append(AttributedString(localized: " and "))
        text.append(privacy)
        text.append(AttributedString("."))
        return text
    }
}
