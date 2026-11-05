import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// SCAN (SPEC §2.5.8, §3.13): full-bleed camera with **QR Code | Paper Card**, Paste Link,
/// flashlight and, in Paper mode, a shutter that reads the card on device.
struct ScanScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @Query(Card.live) private var cards: [Card]
    @Query(Event.active) private var activeEvents: [Event]

    @State private var mode: ScanMode
    @State private var camera: ScanCamera
    @State private var debouncer = ScanDebouncer()
    @State private var isVisible = false
    @State private var isReadingCard = false
    /// The camera preview and the card guide on screen: the photo is read inside the guide only.
    @State private var previewFrame: CGRect = .zero
    @State private var guideFrame: CGRect = .zero
    /// The on-device model that helps read paper cards (iOS 26+ with Apple Intelligence), looked up in Paper mode.
    @State private var cardModel: (any PaperCardLanguageModel)?

    @State private var invalidCode: InvalidCodeAlert?
    @State private var showsInvalidCode: Bool
    @State private var paperNotRead: PaperNotReadAlert?
    @State private var showsPaperNotRead: Bool

    @State private var successFeedback = 0
    @State private var warningFeedback = 0

    /// Parameters exist for previews; the app uses the defaults.
    init(mode: ScanMode = .qr, camera: ScanCamera = ScanCamera(),
         invalidCode: InvalidCodeAlert? = nil, paperNotRead: PaperNotReadAlert? = nil) {
        _mode = State(initialValue: mode)
        _camera = State(initialValue: camera)
        _invalidCode = State(initialValue: invalidCode)
        _showsInvalidCode = State(initialValue: invalidCode != nil)
        _paperNotRead = State(initialValue: paperNotRead)
        _showsPaperNotRead = State(initialValue: paperNotRead != nil)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.access == .authorized {
                cameraLayer
            } else {
                CameraAccessView(access: camera.access, onRequestAccess: requestAccess, onPaste: handlePasted) {
                    #if DEBUG
                    DemoScanMenu(onPayload: handlePasted, onPaperScan: handlePaperScan)
                    #endif
                }
            }
        }
        .navigationTitle("Scan Card")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ScanChrome())
        .environment(\.colorScheme, .dark)
        .alert(InvalidCodeAlert.title, isPresented: $showsInvalidCode, presenting: invalidCode) { alert in
            if let url = alert.url {
                Button("Cancel", role: .cancel) {}
                Button("Open in Safari") { openInSafari(url) }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { alert in
            Text(alert.message)
        }
        .alert(PaperNotReadAlert.title, isPresented: $showsPaperNotRead, presenting: paperNotRead) { alert in
            Button("Enter Manually") { enterManually(alert) }
            Button("Retake", role: .cancel) {}
        } message: { _ in
            Text(PaperNotReadAlert.message)
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .sensoryFeedback(.warning, trigger: warningFeedback)
        .task { await camera.requestAccessIfNeeded() }
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.refreshAccess() }
            // iOS turns the torch off in the background; keep the button truthful.
            if phase == .background { camera.isTorchOn = false }
        }
        .onChange(of: isCameraActive) { _, isActive in
            if isActive {
                debouncer.screenAppeared()
            } else {
                // The feed is torn down under a modal; the torch would otherwise stay lit.
                camera.isTorchOn = false
            }
        }
        .onChange(of: camera.isTorchOn) { camera.applyTorch() }
        .onChange(of: mode) {
            camera.isTorchOn = false
            prepareCardModel()
        }
    }

    private var cameraLayer: some View {
        ZStack {
            if isCameraActive {
                ScanCameraFeed(mode: mode, camera: camera, onCode: handleScanned)
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { previewFrame = $0 }
                    .accessibilityLabel("Camera Viewfinder")
            }
            ViewfinderGuide(mode: mode) { guideFrame = $0 }
        }
        .safeAreaInset(edge: .top) {
            ScanTopBar(eventName: activeEvents.first?.name)
        }
        .safeAreaInset(edge: .bottom) {
            ScanBottomBar(mode: $mode, isReadingCard: isReadingCard, hasTorch: camera.hasTorch,
                          isTorchOn: $camera.isTorchOn, onPaste: handlePasted, onShutter: readPaperCard)
        }
    }

    /// On screen and not covered by a sheet or cover (`onDisappear` doesn't fire under modals).
    private var isCameraActive: Bool {
        ScanCameraPolicy.isCameraActive(isVisible: isVisible, presentations: router.presentations)
    }

    private var ownSlugs: Set<String> {
        Set(cards.map(\.slug).filter { !$0.isEmpty })
    }

    // MARK: Lifecycle

    private func appear() {
        isVisible = true
        prepareCardModel()
        camera.refreshAccess()
        // Coming back from a scanned card: don't re-open it while its code is still in frame
        // (any other code — including one already in view — is handled right away).
        debouncer.screenAppeared()
    }

    private func disappear() {
        isVisible = false
        camera.isTorchOn = false
    }

    private func requestAccess() {
        Task { await camera.requestAccessIfNeeded() }
    }

    // MARK: QR codes & links

    private func handleScanned(_ payload: String) {
        let isBlocked = !isCameraActive || showsInvalidCode || showsPaperNotRead || isReadingCard
        guard debouncer.shouldHandle(payload, isBlocked: isBlocked) else { return }
        route(QRPayloadClassifier.classify(payload, ownSlugs: ownSlugs), source: .camera)
    }

    private func handlePasted(_ text: String) {
        route(QRPayloadClassifier.classify(text, ownSlugs: ownSlugs), source: .clipboard)
    }

    private func route(_ payload: QRPayload, source: ScanSource) {
        switch payload {
        case .metlyCard(let url, let slug):
            successFeedback += 1
            ScanCameraPolicy.show(.scannedCard(ScannedCardPayload(url: url, slug: slug)), router: router)
        case .ownCard:
            successFeedback += 1
            router.showToast(String(localized: "That’s Your Card"), systemImage: "person.crop.rectangle")
        case .vCard(let text):
            successFeedback += 1
            ScanCameraPolicy.show(.scannedCard(ScannedCardPayload(vCard: text)), router: router)
        case .webLink(let url):
            showInvalidCode(InvalidCodeAlert(source: source, url: url, domain: payload.displayDomain))
        case .other:
            showInvalidCode(InvalidCodeAlert(source: source))
        }
    }

    private func showInvalidCode(_ alert: InvalidCodeAlert) {
        warningFeedback += 1
        invalidCode = alert
        showsInvalidCode = true
    }

    private func openInSafari(_ url: URL) {
        router.showToast(String(localized: "Opening Safari"), systemImage: "safari")
        openURL(url)
    }

    // MARK: Paper cards

    /// In Paper mode: finds the on-device model (again, while it is still downloading or switched
    /// off) and loads it ahead of the shutter.
    private func prepareCardModel() {
        guard mode == .paper else { return }
        if cardModel == nil { cardModel = PaperCardModels.available() }
        guard let cardModel else { return }
        Task { await cardModel.prepare() }
    }

    private func readPaperCard() {
        guard !isReadingCard else { return }
        isReadingCard = true
        Task {
            defer { isReadingCard = false }
            do {
                let photo = try await camera.capturePhoto()
                let region = PaperCrop.region(guide: guideFrame, preview: previewFrame, photoSize: photo.size)
                handlePaperScan(await PaperCardReader.read(photo, region: region, model: cardModel))
            } catch {
                handlePaperScan(PaperScan(draft: PaperCardDraft()))
            }
            // Each card gets a fresh session; warm up the next one.
            prepareCardModel()
        }
    }

    private func handlePaperScan(_ scan: PaperScan) {
        if scan.draft.isReadable {
            successFeedback += 1
            PaperScanStore.remember(scan)
            ScanCameraPolicy.show(.paperReview(scan.draft), router: router)
        } else {
            warningFeedback += 1
            paperNotRead = PaperNotReadAlert(imageData: scan.draft.imageData, recognizedText: scan.recognizedText)
            showsPaperNotRead = true
        }
    }

    /// PAPER_REVIEW with empty fields; whatever text was read is still offered under Recognized Text.
    private func enterManually(_ alert: PaperNotReadAlert) {
        let draft = PaperCardDraft(imageData: alert.imageData)
        if !alert.recognizedText.isEmpty {
            PaperScanStore.remember(PaperScan(draft: draft, recognizedText: alert.recognizedText))
        }
        ScanCameraPolicy.show(.paperReview(draft), router: router)
    }
}
