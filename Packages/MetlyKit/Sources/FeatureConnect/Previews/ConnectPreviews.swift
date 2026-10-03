#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CONNECT · SPEC Appendix A #21–#26 plus the permission / privacy / offline states.

#Preview("Connect · live demo") {
    // Real model: the demo transport "finds" the mock world's people; Kamila accepts, Nodira never answers.
    ConnectView(cardID: nil)
        .metlyPreview()
}

#Preview("Nearby · searching") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model())
        .metlyPreview()
}

#Preview("Nearby · list") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(people: ConnectPreviewData.people))
        .metlyPreview()
}

#Preview("Nearby · waiting") {
    let kamila = ConnectPreviewData.kamila
    ConnectScreen(requestedCardID: nil,
                  model: ConnectPreviewData.model(phase: .waiting(kamila.asPeer, method: .nearby),
                                                  people: ConnectPreviewData.people))
        .metlyPreview()
}

#Preview("Nearby · no response") {
    let nodira = ConnectPreviewData.nodira
    ConnectScreen(requestedCardID: nil,
                  model: ConnectPreviewData.model(notice: .noResponse(firstName: nodira.firstName),
                                                  people: ConnectPreviewData.people))
        .metlyPreview()
}

#Preview("Nearby · no one nearby") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(hasWaitedForPeers: true))
        .metlyPreview(.empty)
}

#Preview("Nearby · Show in Nearby off") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(availability: .hiddenFromNearby))
        .metlyPreview()
}

#Preview("Nearby · Local Network denied") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(availability: .localNetworkDenied))
        .metlyPreview()
}

#Preview("Nearby · offline") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(availability: .offline))
        .metlyPreview(online: false)
}

#Preview("Nearby · list · dark, accessibility size") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(people: ConnectPreviewData.people))
        .metlyPreview()
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.dark)
}

#Preview("Tap Phones · idle") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(.tapPhones))
        .metlyPreview()
}

#Preview("Tap Phones · bump fallback") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(.tapPhones, tapCapability: .bump))
        .metlyPreview()
}

#Preview("Tap Phones · detected") {
    let kamila = ConnectPreviewData.kamila
    ConnectScreen(requestedCardID: nil,
                  model: ConnectPreviewData.model(.tapPhones, phase: .waiting(kamila.asPeer, method: .tapPhones),
                                                  people: [kamila], tapStatus: .detected(kamila)))
        .metlyPreview()
}

#Preview("Tap Phones · receiving") {
    let kamila = ConnectPreviewData.kamila
    ConnectScreen(requestedCardID: nil,
                  model: ConnectPreviewData.model(.tapPhones, people: [kamila], tapStatus: .receiving(kamila)))
        .metlyPreview()
}

#Preview("Tap Phones · unsupported") {
    ConnectScreen(requestedCardID: nil, model: ConnectPreviewData.model(.tapPhones, tapCapability: .unsupported))
        .metlyPreview()
}

#Preview("Incoming request") {
    IncomingRequestPreviewHost(model: ConnectPreviewData.model(people: ConnectPreviewData.people))
        .metlyPreview()
}

#Preview("Incoming request · while waiting") {
    let kamila = ConnectPreviewData.kamila
    IncomingRequestPreviewHost(model: ConnectPreviewData.model(phase: .waiting(kamila.asPeer, method: .nearby),
                                                               people: ConnectPreviewData.people))
        .metlyPreview()
}
#endif
