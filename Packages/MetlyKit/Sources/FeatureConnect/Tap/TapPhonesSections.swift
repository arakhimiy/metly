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
                content
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

    @ViewBuilder
    private var content: some View {
        switch model.tapStatus {
        case .ready:
            TapReadyView(model: model)
        case .detected(let person):
            TapProgressView(person: person, detail: "Sending your card…", showsCancel: model.machine.isWaiting,
                            onCancel: { model.cancelRequest() })
        case .receiving(let person):
            TapProgressView(person: person, detail: "Accept their request when it appears.", showsCancel: false,
                            onCancel: {})
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// "Hold Phones Together" + the bump illustration (and "Simulate Tap" in the demo world).
private struct TapReadyView: View {
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
                Button("Simulate Tap", systemImage: "hand.tap") {
                    model.simulateTap()
                }
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

/// "Connecting with {first}…" after the phones touched.
private struct TapProgressView: View {
    let person: NearbyPerson
    let detail: String
    let showsCancel: Bool
    let onCancel: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 14) {
            PersonAvatar(name: person.fullName, url: person.avatarURL, size: avatarSize)
            VStack(spacing: 4) {
                Text(ConnectCopy.connectingWith(person.firstName))
                    .font(.title3.bold())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            ProgressView()
            if showsCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel Request to \(person.firstName)")
            }
        }
    }
}

/// Two iPhones held top to top, gently bumping (static with Reduce Motion).
struct TapIllustration: View {
    var isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phases: [Bool] = isAnimating && !reduceMotion ? [false, true] : [false]
        PhaseAnimator(phases) { together in
            VStack(spacing: together ? 2 : 14) {
                Image(systemName: "iphone.gen3")
                    .rotationEffect(.degrees(180))
                Image(systemName: "iphone.gen3")
            }
            .overlay {
                Image(systemName: "wave.3.up")
                    .font(.footnote.weight(.bold))
                    .opacity(together ? 1 : 0)
            }
        } animation: { together in
            together ? .spring(duration: 0.3, bounce: 0.45) : .easeInOut(duration: 1.1)
        }
        .font(.largeTitle)
        .imageScale(.large)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }
}
