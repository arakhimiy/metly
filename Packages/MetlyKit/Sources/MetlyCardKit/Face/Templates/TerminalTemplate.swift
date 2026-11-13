import MetlyCore
import SwiftUI

/// Terminal — SF Mono; `~/company $ whoami`, the name with a block cursor, `# title @ company`, then
/// contacts as aligned `key value` columns with accent keys; QR bottom-right.
struct TerminalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.u(1.2)) {
            promptLine
            nameLine
            if !comment.isEmpty {
                CardText(text: "# \(comment)", style: style, size: 2.7, color: style.muted, lineLimit: 2)
            }
            Spacer(minLength: 0)
            CardCapWidth(maxWidth: style.u(model.showsQR ? 64 : 84)) {
                CardLabelledContacts(contacts: model.contacts, style: style, fontSize: 2.8, labelColor: style.accent,
                                     spacing: 0.9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(style.u(8))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 15, cornerRadius: 1.2).padding(style.u(7))
            }
        }
    }

    private var comment: String {
        [model.jobTitle.lowercased(), model.company.isEmpty ? "" : "@ \(model.company.lowercased())"]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var folder: String {
        let slug = model.company.lowercased().filter { $0.isLetter || $0.isNumber }
        return slug.isEmpty ? Brand.appName.lowercased() : slug
    }

    private var promptLine: some View {
        let path = Text(verbatim: "~/\(folder)")
        let dollar = Text(verbatim: "$").foregroundStyle(style.accent)
        return Text("\(path) \(dollar) \(Text(verbatim: "whoami"))")
            .font(style.font(2.6))
            .foregroundStyle(style.muted)
            .lineLimit(1)
    }

    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.u(1)) {
            CardText(text: model.fullName, style: style, size: 5.2, weight: .semibold, tracking: -0.02, minimumScale: 0.6)
            Rectangle().fill(style.accent)
                .frame(width: style.u(2.4), height: style.u(4.2))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - style.u(0.4) }
        }
    }
}
