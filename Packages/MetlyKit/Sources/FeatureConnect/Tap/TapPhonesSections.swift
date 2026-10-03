import MetlyCore
import SwiftUI

/// Tap Phones mode (SPEC §2.5.26): "Hold the top of your iPhone near theirs" until the phones
/// touch, then "Connecting with {first}…". Emits list `Section`s.
struct TapPhonesSections: View {
    let model: ConnectModel
    let onUseNearby: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        if model.tapCapability == .unsupported {
            Section {
                ConnectUnavailableView(reason: .tapUnsupported, onUseNearby: onUseNearby)
            }
        } else {
            Section {
                TapStatusView(model: model)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } footer: {
                if model.tapCapability == .bump, model.tapStatus == .ready {
                    Text(ConnectCopy.tapBumpFooter)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .listRowBackground(Color.clear)

            if model.isNearbyInteractionDenied {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nearby Interactions are off for \(Brand.appName). Tapping still works, but turning them on makes it more reliable.")
                                .font(.subheadline)
                            Button("Open Settings", action: openSettings)
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                    } icon: {
                        Image(systemName: "wave.3.right")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
