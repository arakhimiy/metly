import SwiftUI

/// The Tap Phones hero for the current `TapStatus`.
struct TapStatusView: View {
    let model: ConnectModel

    var body: some View {
        switch model.tapStatus {
        case .ready:
            TapReadyView(model: model)
        case .detected(let person):
            TapProgressView(person: person, detail: "Sending your card…", onCancel: cancelAction)
        case .receiving(let person):
            TapProgressView(person: person, detail: "Accept their request when it appears.")
        }
    }

    /// Cancel is offered while this phone's request is outstanding.
    private var cancelAction: (() -> Void)? {
        guard model.machine.isWaiting else { return nil }
        return model.cancelRequest
    }
}
