import MetlyDesign
import SwiftUI

/// Mode switch · hint pill · Paste Link · Shutter (Paper mode) · Flashlight.
struct ScanBottomBar: View {
    @Binding var mode: ScanMode
    let isReadingCard: Bool
    let hasTorch: Bool
    @Binding var isTorchOn: Bool
    let onPaste: (String) -> Void
    let onShutter: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ScanModePicker(mode: $mode)
            ScanHintPill(text: isReadingCard ? String(localized: "Reading the card…") : mode.hint, showsProgress: isReadingCard)

            HStack(alignment: .center, spacing: 16) {
                PasteLinkButton(onPaste: onPaste)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if mode == .paper {
                    ShutterButton(isBusy: isReadingCard, action: onShutter)
                }

                Group {
                    if hasTorch {
                        TorchButton(isOn: $isTorchOn)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(.smooth, value: mode)
    }
}

private struct ScanHintPill: View {
    let text: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
            }
            Text(text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassOrMaterial(in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Camera-style shutter (no system equivalent exists).
private struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                Circle()
                    .fill(.white.opacity(isBusy ? 0.5 : 1))
                    .padding(8)
            }
            .frame(width: 76, height: 76)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel("Take Photo")
        .accessibilityHint("Reads the business card inside the frame")
    }
}

private struct TorchButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button("Flashlight", systemImage: isOn ? "flashlight.on.fill" : "flashlight.off.fill", action: toggle)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(isOn ? .yellow : .white)
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(.circle)
            .glassOrMaterial(in: .circle, interactive: true)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .sensoryFeedback(.selection, trigger: isOn)
    }

    private func toggle() {
        isOn.toggle()
    }
}
