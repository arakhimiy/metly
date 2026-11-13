import MetlyCardKit
import MetlyCore
import SwiftUI
import WidgetKit

/// WIDGETS_GALLERY (push from Profile): every widget with a live preview of the user's own data, how to
/// add them, and the Siri / Shortcuts phrases.
struct WidgetsGalleryScreen: View {
    @State private var snapshot: WidgetSnapshot?
    private let loadsLiveData: Bool

    /// - Parameter snapshot: fixed data for previews; nil loads (and refreshes) the published snapshot.
    init(snapshot: WidgetSnapshot? = nil) {
        _snapshot = State(initialValue: snapshot)
        loadsLiveData = snapshot == nil
    }

    var body: some View {
        let data = GalleryData(snapshot: snapshot, now: .now)
        List {
            FollowUpsGallerySection(data: data)
            LockScreenGallerySection(data: data)
            HomeScreenGallerySection(data: data)
            ControlCenterGallerySection(design: data.wallpaperDesign)
            HowToAddSection()
            ShortcutPhrasesSection()
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard loadsLiveData else { return }
            snapshot = WidgetSnapshotPublisher.shared?.publishNow() ?? WidgetSnapshotStore.appGroup.load()
        }
    }
}

/// Preview content resolved once per render. Card previews fall back to demo data when the user has
/// no card yet, so the page always shows what the widgets look like.
struct GalleryData {
    let now: Date
    let card: CardWidgetContent
    let followUps: FollowUpsWidgetContent
    let usesSampleCard: Bool

    init(snapshot: WidgetSnapshot?, now: Date) {
        self.now = now
        let live = CardWidgetContent.resolve(snapshot: snapshot, cardID: nil, at: now)
        if live.display != nil {
            card = live
            usesSampleCard = false
        } else {
            card = CardWidgetContent.resolve(snapshot: .sample(now: now), cardID: nil, at: now)
            usesSampleCard = true
        }
        let source = snapshot?.isSignedIn == true ? snapshot : .sample(now: now)
        followUps = FollowUpsWidgetContent.resolve(snapshot: source, at: now)
    }

    var wallpaperDesign: CardDesign { card.display?.card.design ?? CardDesign() }
}

// MARK: - Sections

struct FollowUpsGallerySection: View {
    let data: GalleryData

    var body: some View {
        Section {
            WidgetShowcaseRow(title: "Follow-ups", detail: "Medium · Reminders due today, with a Done button.",
                              design: data.wallpaperDesign,
                              accessibilityPreview: Text("Preview of the Follow-ups widget")) {
                HomeWidgetPreview(size: WidgetPreviewSize.medium, background: WidgetBackgrounds.standard) {
                    FollowUpsWidgetView(content: data.followUps, now: data.now) { _ in FollowUpDoneGlyph() }
                }
            }
        } header: {
            Text("Follow-ups")
        } footer: {
            Text("Medium widget. Tap a reminder to open it in \(Brand.appName), or tap the circle to mark it done.")
        }
    }
}

struct LockScreenGallerySection: View {
    let data: GalleryData

    var body: some View {
        Section {
            WidgetShowcaseRow(title: "QR Code", detail: "Rectangular and circular · Scan to connect.",
                              design: data.wallpaperDesign, dimmedWallpaper: true,
                              accessibilityPreview: Text("Preview of the Lock Screen QR widgets")) {
                HStack(spacing: 16) {
                    LockQRRectangularView(content: data.card) { LockPreviewBackdrop() }
                        .frame(width: WidgetPreviewSize.rectangular.width, height: WidgetPreviewSize.rectangular.height)
                    LockQRCircularView(content: data.card) { Circle().fill(.white.opacity(0.18)) }
                        .frame(width: WidgetPreviewSize.circular.width, height: WidgetPreviewSize.circular.height)
                }
                .foregroundStyle(.white)
                .environment(\.widgetRenderingMode, .vibrant)
                .environment(\.colorScheme, .dark)
                .dynamicTypeSize(...DynamicTypeSize.large)
            }
        } header: {
            Text("Lock Screen")
        } footer: {
            Text("Your QR shows right on the Lock Screen, so people can scan it without you unlocking. Tap it to open it full screen.")
        }
    }
}

struct LockPreviewBackdrop: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.18))
    }
}

struct HomeScreenGallerySection: View {
    let data: GalleryData

    var body: some View {
        let design = data.wallpaperDesign
        Section {
            WidgetShowcaseRow(title: "My QR", detail: "Small · Opens your QR code in one tap.", design: design,
                              accessibilityPreview: Text("Preview of the My QR widget")) {
                HomeWidgetPreview(size: WidgetPreviewSize.small, background: WidgetBackgrounds.card(design),
                                  contentMargin: 12) {
                    MyQRWidgetView(content: data.card)
                }
            }
            WidgetShowcaseRow(title: "Card", detail: "Medium · Your card and this week’s new connections.", design: design,
                              accessibilityPreview: Text("Preview of the Card widget")) {
                HomeWidgetPreview(size: WidgetPreviewSize.medium, background: WidgetBackgrounds.standard) {
                    CardWidgetView(content: data.card)
                }
            }
        } header: {
            Text("Home Screen")
        } footer: {
            Text(data.usesSampleCard
                 ? "Previews show sample details until you create a card. Touch and hold a widget, then tap Edit Widget to choose which card it shows."
                 : "Touch and hold a widget, then tap Edit Widget to choose which card it shows.")
        }
    }
}

struct ControlCenterGallerySection: View {
    let design: CardDesign

    var body: some View {
        Section {
            WidgetShowcaseRow(title: "Show My QR", detail: "Control · Opens your QR full screen from anywhere.",
                              design: design, dimmedWallpaper: true,
                              accessibilityPreview: Text("Preview of the Show My QR control")) {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode")
                        .font(.title2)
                        .frame(width: 60, height: 60)
                        .background(.white.opacity(0.2), in: .circle)
                    Text("Show My QR")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .dynamicTypeSize(...DynamicTypeSize.large)
            }
        } header: {
            Text("Control Center")
        } footer: {
            Text("You can also put it on the Lock Screen or the Action button.")
        }
    }
}
