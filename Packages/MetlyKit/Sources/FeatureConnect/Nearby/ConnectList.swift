import MetlyData
import SwiftUI

/// CONNECT's scrolling content: mode picker + event pill, the unavailable state or the current
/// mode's sections (with any notice), and the card to share.
struct ConnectList: View {
    @Bindable var model: ConnectModel
    let cards: [Card]
    let profile: Profile?
    let activeEventName: String?
    let onShowQR: () -> Void

    var body: some View {
        List {
            Section {
                if ConnectMode.offered.count > 1 {
                    Picker("Mode", selection: $model.mode) {
                        ForEach(ConnectMode.offered) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let activeEventName {
                    EventPill(name: activeEventName)
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if let reason = model.availability.unavailableReason {
                Section {
                    ConnectUnavailableView(reason: reason, onShowQR: onShowQR,
                                           onTurnOnNearby: model.turnOnShowInNearby, onRetry: model.retry)
                }
            } else {
                if let notice = model.machine.notice {
                    Section {
                        ConnectNoticeRow(notice: notice, onShowQR: notice.offersQR ? onShowQR : nil,
                                         onDismiss: model.dismissNotice)
                    }
                }
                switch model.mode {
                case .nearby:
                    NearbySections(model: model, onShowQR: onShowQR)
                case .tapPhones:
                    TapPhonesSections(model: model, onUseNearby: useNearby)
                }
            }

            if !cards.isEmpty {
                CardChooserSection(cards: cards, profile: profile, selection: $model.selectedCardID,
                                   isLocked: model.machine.isWaiting || model.machine.isAccepting)
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: model.peers)
        .animation(.default, value: model.machine)
    }

    private func useNearby() {
        model.mode = .nearby
    }
}

private extension ConnectAvailability {
    var unavailableReason: ConnectUnavailableView.Reason? {
        switch self {
        case .starting, .active: nil
        case .hiddenFromNearby: .hiddenFromNearby
        case .localNetworkDenied: .localNetworkDenied
        case .offline: .offline
        case .failed(let message): .failed(message)
        }
    }
}

private extension ConnectMachine.Notice {
    /// "Show My QR" belongs to the no-response notice only.
    var offersQR: Bool {
        if case .noResponse = self { return true }
        return false
    }
}
