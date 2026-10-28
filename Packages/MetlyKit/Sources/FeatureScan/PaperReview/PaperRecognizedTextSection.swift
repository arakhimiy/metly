import SwiftUI

/// "Recognized Text" (collapsed by default): every piece of text the camera read, with what it is
/// used for. Tapping a line opens **Use As** → Name / Job Title / Company / Phone / Email /
/// Website / Telegram / LinkedIn / Ignore — the fix when something landed in the wrong field.
struct PaperRecognizedTextSection: View {
    let lines: [String]
    let details: PaperCardDetails
    let onUse: (String, PaperLineUse) -> Void

    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    RecognizedLineRow(line: line, uses: details.uses(of: line), onUse: { onUse(line, $0) })
                }
            } label: {
                Label("Recognized Text", systemImage: "text.viewfinder")
            }
        } footer: {
            if isExpanded {
                Text("Tap a line to use it for another field.")
            }
        }
    }
}

private struct RecognizedLineRow: View {
    let line: String
    let uses: [PaperLineUse]
    let onUse: (PaperLineUse) -> Void

    var body: some View {
        Menu {
            Section("Use As") {
                ForEach(PaperLineUse.allCases.filter { $0 != .ignore }) { use in
                    Button {
                        onUse(use)
                    } label: {
                        if uses.contains(use) {
                            Label(use.title, systemImage: "checkmark")
                        } else {
                            Label(use.title, systemImage: use.symbolName)
                        }
                    }
                }
            }
            Button("Ignore", systemImage: PaperLineUse.ignore.symbolName) { onUse(.ignore) }
                .disabled(uses.isEmpty)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(line)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(usesTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .accessibilityLabel(line)
        .accessibilityValue(uses.isEmpty ? String(localized: "Not Used") : usesTitle)
        .accessibilityHint("Choose which field this text fills.")
    }

    private var usesTitle: String {
        uses.isEmpty ? String(localized: "Not Used") : uses.map(\.title).formatted(.list(type: .and))
    }
}
