import MetlyCardKit
import MetlyCore
import SwiftUI

/// Per-format option lists (SPEC §2.5.25): Resolution + Corners · Page · Pass · Device.
struct ExportOptionsSections: View {
    @Binding var options: ExportOptions
    let linkStatus: CardLinkStatus

    var body: some View {
        switch options.tab {
        case .image:
            Section("Resolution") {
                ForEach(ExportScale.allCases) { scale in
                    ExportOptionRow(title: scale.title, subtitle: scale.subtitle, isSelected: options.scale == scale) {
                        options.scale = scale
                    }
                }
            }
            Section("Corners") {
                ForEach(ExportCorners.allCases) { corners in
                    ExportOptionRow(title: corners.title, subtitle: corners.subtitle, isSelected: options.corners == corners) {
                        options.corners = corners
                    }
                }
            }
        case .pdf:
            Section("Page") {
                ForEach(ExportPDFLayout.allCases) { layout in
                    ExportOptionRow(title: layout.title, subtitle: layout.subtitle, isSelected: options.pdfLayout == layout) {
                        options.pdfLayout = layout
                    }
                }
            }
        case .wallet:
            Section {
                ExportOptionRow(title: "Apple Wallet", subtitle: "QR on the pass, updates when you edit", isSelected: true) {}
            } header: {
                Text("Pass")
            } footer: {
                if linkStatus.url == nil {
                    Text("Apple Wallet becomes available once your card is published.")
                }
            }
        case .lockScreen:
            Section("Device") {
                ForEach(CardExporter.LockScreenDevice.allCases) { device in
                    ExportOptionRow(title: device.title, subtitle: device.subtitle, isSelected: options.device == device) {
                        options.device = device
                    }
                }
            }
        }

        Section {
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The QR keeps a 4-module quiet zone and error correction level M in every format.")
                if linkStatus.url == nil, options.tab != .wallet {
                    Text("Your card isn’t published yet, so the QR shares your contact details. Export again once it’s published to use your link.")
                }
                Text("Exports show only your Public details.")
            }
        }
        .sensoryFeedback(.selection, trigger: options)
    }
}
