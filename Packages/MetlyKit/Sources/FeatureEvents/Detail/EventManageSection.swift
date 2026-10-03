import MetlyDesign
import SwiftUI

/// Export to CSV (PRO on Free), Resume Event (last event, ended) and End Event (active, destructive).
struct EventManageSection: View {
    let isActive: Bool
    let canResume: Bool
    let isPro: Bool
    let onExport: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        Section {
            Button(action: onExport) {
                HStack {
                    Label("Export to CSV", systemImage: "tablecells")
                    Spacer(minLength: 8)
                    if !isPro {
                        ProBadge()
                    }
                }
                .contentShape(.rect)
            }
            if canResume {
                Button("Resume Event", systemImage: "play.circle", action: onResume)
            }
            if isActive {
                Button("End Event", systemImage: "flag.checkered", role: .destructive, action: onEnd)
            }
        } footer: {
            if isActive {
                Text("The event also ends by itself after the last day.")
            } else if canResume {
                Text("Resume to keep adding new connections to this event.")
            }
        }
    }
}
