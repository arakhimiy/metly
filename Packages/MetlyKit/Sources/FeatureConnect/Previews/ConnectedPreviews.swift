#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CONNECTED · SPEC Appendix A #28.

#Preview("Connected · with event") {
    // Kamila, met at Tashkent Tech Week (active event): Where You Met is auto-filled.
    ConnectedView(connectionID: PreviewSeed.firstConnectionID)
        .metlyPreview()
}

#Preview("Connected · without event") {
    // No active event: Place is filled from the current location when allowed.
    ConnectedPreviewHost()
        .metlyPreview(.empty)
}

#Preview("Connected · several phones") {
    // They shared a work and a home number too: listed under Phone Numbers, all saved to Contacts.
    ConnectedPreviewHost(additionalPhones: [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                            LabeledPhone(label: .home, value: "+998 66 233 00 00")])
        .metlyPreview(.empty)
}

#Preview("Connected · Pro, dark") {
    ConnectedView(connectionID: PreviewSeed.firstConnectionID)
        .metlyPreview(plan: .pro)
        .preferredColorScheme(.dark)
}

#Preview("Connected · accessibility size") {
    ConnectedPreviewHost()
        .metlyPreview(.empty)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Connected · not found") {
    ConnectedView(connectionID: UUID())
        .metlyPreview(.empty)
}
#endif
