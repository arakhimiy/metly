import MetlyDesign
import SwiftUI

/// "Hold Phones Together" + the bump illustration (and "Simulate Tap" in the demo world).
struct TapReadyView: View {
    let model: ConnectModel

    var body: some View {
        VStack(spacing: 16) {
            TapIllustration(isAnimating: model.isTapDetectionWanted)
            VStack(spacing: 6) {
                Text(ConnectCopy.tapTitle)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(ConnectCopy.tapMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            if showsSimulateButton {
                Button("Simulate Tap", systemImage: "hand.tap", action: model.simulateTap)
                    .secondaryButtonStyle()
                    .disabled(!model.isTapDetectionWanted || !model.machine.canSendRequest)
            }
        }
    }

    private var showsSimulateButton: Bool {
        #if DEBUG
        model.canSimulateTap
        #else
        false
        #endif
    }
}
