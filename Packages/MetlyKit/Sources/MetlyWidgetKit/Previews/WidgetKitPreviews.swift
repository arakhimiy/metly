import MetlyCore
import SwiftUI
import WidgetKit

// WIDGETS_GALLERY states. (The widgets themselves have `#Preview(as:)` previews in the extension.)

#Preview("Widgets gallery") {
    NavigationStack { WidgetsGalleryScreen(snapshot: .sample()) }
}

#Preview("Widgets gallery · dark") {
    NavigationStack { WidgetsGalleryScreen(snapshot: .sample()) }
        .preferredColorScheme(.dark)
}

#Preview("Widgets gallery · no reminders") {
    NavigationStack { WidgetsGalleryScreen(snapshot: .sampleEmpty()) }
}

#Preview("Widgets gallery · signed out / no data") {
    NavigationStack { WidgetsGalleryScreen(snapshot: .signedOut()) }
}

#Preview("Widgets gallery · accessibility text") {
    NavigationStack { WidgetsGalleryScreen(snapshot: .sample()) }
        .dynamicTypeSize(.accessibility2)
}

// Shared widget views outside WidgetKit, per rendering mode.

#Preview("QR · rendering modes", traits: .sizeThatFitsLayout) {
    let content = CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now)
    HStack(spacing: 16) {
        MyQRWidgetView(content: content)
            .padding(12)
            .frame(width: 158, height: 158)
            .background(WidgetBackgrounds.card(content.display!.card.design), in: .rect(cornerRadius: 22))
        MyQRWidgetView(content: content)
            .padding(12)
            .frame(width: 158, height: 158)
            .background(.indigo.gradient, in: .rect(cornerRadius: 22))
            .environment(\.widgetRenderingMode, .accented)
        LockQRCircularView(content: content) { Circle().fill(.white.opacity(0.2)) }
            .frame(width: 72, height: 72)
            .foregroundStyle(.white)
            .environment(\.widgetRenderingMode, .vibrant)
    }
    .padding()
    .background(.black)
}
