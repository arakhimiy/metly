import MetlyCore
import MetlyDesign
import SwiftUI

/// "CSV File · {N} people · notes and follow-ups included".
struct ExportSummarySection: View {
    let peopleCount: Int

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CSV File")
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "tablecells")
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Format")
        } footer: {
            Text("Opens in Numbers, Excel and other spreadsheet apps.")
        }
    }

    private var subtitle: String {
        let people = peopleCount == 1 ? String(localized: "1 person", bundle: .appStrings) : String(localized: "\(peopleCount) people", bundle: .appStrings)
        return String(localized: "\(people) · notes and follow-ups included", bundle: .appStrings)
    }
}

/// Field toggles (Name is always included).
struct ExportFieldsSection: View {
    @Binding var options: [ExportColumnOption]

    var body: some View {
        Section {
            ForEach($options) { $option in
                Toggle(option.column.title, isOn: $option.isIncluded)
                    .disabled(option.column.isRequired)
            }
        } header: {
            Text("Included")
        } footer: {
            Text("Private notes are included only in your export. Nothing is sent to the people you met.")
        }
    }
}

/// First rows of the file as a small table that scrolls sideways.
struct CSVPreviewSection: View {
    let rows: [EventCSVRow]
    let columns: [EventCSVColumn]

    private static let previewCount = 3

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ForEach(columns) { column in
                            CSVPreviewCell(text: column.header, isHeader: true)
                        }
                    }
                    Divider()
                    ForEach(rows.prefix(Self.previewCount)) { row in
                        GridRow {
                            ForEach(columns) { column in
                                CSVPreviewCell(text: row[column], isHeader: false)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CSV Preview")
        } header: {
            Text("Preview")
        } footer: {
            if rows.count > Self.previewCount {
                Text("Showing \(Self.previewCount) of \(rows.count) rows.")
            }
        }
    }
}

private struct CSVPreviewCell: View {
    let text: String
    let isHeader: Bool

    @ScaledMetric(relativeTo: .caption) private var maxWidth: CGFloat = 160

    var body: some View {
        Text(text.isEmpty ? "—" : text)
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(isHeader || !text.isEmpty ? .primary : .tertiary)
            .lineLimit(1)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .accessibilityLabel(text.isEmpty ? String(localized: "Empty", bundle: .appStrings) : text)
    }
}

/// Bottom CTA: Pro → share the generated file; Free → Upgrade to Export (PAYWALL).
struct ExportCallToAction: View {
    let isPro: Bool
    let peopleCount: Int
    let fileURL: URL?
    let eventName: String
    let writeFailed: Bool
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isPro {
                if let fileURL {
                    ShareLink(item: fileURL,
                              preview: SharePreview(EventCSV.fileName(for: eventName), image: Image(systemName: "tablecells"))) {
                        Label(exportTitle, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                } else {
                    Button(action: {}) {
                        Label(exportTitle, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                    .disabled(true)
                }
                if writeFailed {
                    Text("Couldn’t create the file. Try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Button(action: onUpgrade) {
                    Label("Upgrade to Export", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                Text("Exporting events is part of \(Brand.proName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var exportTitle: String {
        peopleCount == 1 ? String(localized: "Export 1 Contact", bundle: .appStrings) : String(localized: "Export \(peopleCount) Contacts", bundle: .appStrings)
    }
}
