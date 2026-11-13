import MetlyCardKit
import MetlyCore
import SwiftUI

/// Mock-up of the generic Wallet pass the server signs: app name, card name, Name, Title, Company, QR.
struct WalletPassPreview: View {
    let design: CardDesign
    let content: CardFaceContent
    let cardName: String

    var body: some View {
        let colors = design.colors
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(Brand.appName, systemImage: "person.crop.rectangle.stack.fill")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(cardName)
                    .font(.subheadline)
            }
            PassField(label: "Name", value: content.fullName.isEmpty ? "–" : content.fullName, isPrimary: true)
            HStack(alignment: .top, spacing: 16) {
                if !content.jobTitle.isEmpty {
                    PassField(label: "Title", value: content.jobTitle, isPrimary: false)
                }
                if !content.company.isEmpty {
                    PassField(label: "Company", value: content.company, isPrimary: false)
                }
            }
            QRCodeView(payload: content.qrPayload)
                .frame(width: 132)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .foregroundStyle(colors.foreground.color)
        .background(colors.background.color, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .frame(maxWidth: 320)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct PassField: View {
    let label: String
    let value: String
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .opacity(0.7)
            Text(value)
                .font(isPrimary ? .title3.bold() : .subheadline)
                .lineLimit(2)
        }
    }
}
