import MetlyCore
import SwiftUI

/// 7 · Terminal — forced SF Mono; `~/metly $ whoami`, name with an accent cursor, `# role`,
/// contacts as `key value` with accent keys; QR bottom-right 22 %.
struct TerminalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.u(1.2)) {
            promptLine
            nameLine
            if !model.role.isEmpty {
                CardText(text: "# \(model.role)", style: style, size: 3, color: style.muted, lineLimit: 2)
            }
            Spacer(minLength: 0)
            CardCapWidth(maxWidth: style.u(58)) {
                VStack(alignment: .leading, spacing: style.u(1)) {
                    ForEach(model.contacts) { contact in
                        let key = Text(verbatim: contact.kind.terminalKey).foregroundStyle(style.accent)
                        Text("\(key) \(Text(verbatim: contact.value))")
                            .font(style.font(3))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(style.u(6))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 22, cornerRadius: 1.4).padding(style.u(6))
            }
        }
    }

    private var promptLine: some View {
        let path = Text(verbatim: "~/\(Brand.appName.lowercased())")
        let dollar = Text(verbatim: "$").foregroundStyle(style.accent)
        return Text("\(path) \(dollar) \(Text(verbatim: "whoami"))")
            .font(style.font(3))
            .foregroundStyle(style.muted)
            .lineLimit(1)
    }

    private var nameLine: some View {
        let name = Text(verbatim: model.fullName).fontWeight(.semibold)
        let cursor = Text(verbatim: "_").foregroundStyle(style.accent).fontWeight(.regular)
        return Text("\(name)\(cursor)")
            .font(style.font(5.4))
            .tracking(style.tracking(-0.02, size: 5.4))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
