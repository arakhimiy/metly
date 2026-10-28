import MetlyDesign
import SwiftUI

/// The active event pill (the mode switch sits at the bottom, in thumb reach — `ScanModePicker`).
struct ScanTopBar: View {
    let eventName: String?

    var body: some View {
        if let eventName {
            EventPill(name: eventName)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }
}

/// **QR Code | Paper Card** — system segmented control on floating material.
struct ScanModePicker: View {
    @Binding var mode: ScanMode

    var body: some View {
        Picker("Scan Mode", selection: $mode) {
            ForEach(ScanMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        .glassOrMaterial(in: .rect(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 360)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

/// "● Tashkent Tech Week" — new connections are tagged with this event.
private struct EventPill: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassOrMaterial(in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Event: \(name)")
        .accessibilityHint("New connections are added to this event")
    }
}
