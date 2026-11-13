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
            // Wrap, never truncate: the Uzbek and Russian sentences need two lines.
            .fixedSize(horizontal: false, vertical: true)
            .tint(.accentColor)
    }

    static var attributedText: AttributedString {
        var terms = AttributedString(localized: "Terms", bundle: .appStrings)
        terms.link = Brand.termsURL
        var privacy = AttributedString(localized: "Privacy Policy", bundle: .appStrings)
        privacy.link = Brand.privacyURL

        var text = AttributedString(localized: "By continuing, you agree to the ", bundle: .appStrings)
        text.append(terms)
        text.append(AttributedString(localized: " and ", bundle: .appStrings))
        text.append(privacy)
        text.append(AttributedString("."))
        return text
    }
}
