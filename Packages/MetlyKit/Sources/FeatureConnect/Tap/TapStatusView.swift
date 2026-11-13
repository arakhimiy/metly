import SwiftUI

/// The Tap Phones hero for the current `TapStatus`.
struct TapStatusView: View {
    let model: ConnectModel

    var body: some View {
        switch model.tapStatus {
        case .ready:
            TapReadyView(model: model)
        case .detected(let person):
            TapProgressView(person: person, detail: String(localized: "Sending your card…", bundle: .appStrings), onCancel: cancelAction)
        case .receiving(let person):
            TapProgressView(person: person, detail: String(localized: "Accept their request when it appears.", bundle: .appStrings))
        }
    }

    /// Cancel is offered while this phone's request is outstanding.
    private var cancelAction: (() -> Void)? {
        guard model.machine.isWaiting else { return nil }
        return model.cancelRequest
    }
}
