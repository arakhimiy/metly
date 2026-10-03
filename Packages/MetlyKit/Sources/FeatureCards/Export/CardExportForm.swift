import MetlyCapture
import MetlyCore
import MetlyData
import SwiftUI

/// CARD_EXPORT body: Image · PDF · Wallet · Lock Screen, a preview of the real output and the
/// save/share actions. Every export uses `.public` content (it leaves the device).
struct CardExportForm: View {
    let card: Card
    let profile: Profile?

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.walletPassProvider) private var walletPassProvider

    @State private var options: ExportOptions
    @State private var rendered: RenderedExport?
    @State private var failedOutput: ExportOutput?
    @State private var savedOutput: ExportOutput?
    @State private var successCount = 0
    @State private var isExportingPDF = false
    @State private var settingsAlert: SettingsAlert?
    @State private var errorMessage: String?
    @State private var wallet = WalletAddFlow()

    init(card: Card, profile: Profile?, initialTab: CardExportTab) {
        self.card = card
        self.profile = profile
        _options = State(initialValue: ExportOptions(tab: initialTab))
    }

    var body: some View {
        let content = CardContentFactory.shareable(card, profile: profile)
        let linkStatus = CardLinkStatus(url: card.url, isOnline: services.network.isOnline)
        NavigationStack {
            Form {
                Section {
                    ExportPreviewView(tab: options.tab, rendered: rendered, isRendering: isRendering,
                                      design: card.design, content: content, cardName: card.name)
                }
                .listRowBackground(Color.clear)

                ExportOptionsSections(options: $options, linkStatus: linkStatus)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Format", selection: $options.tab) {
                    ForEach(CardExportTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: router.dismiss)
                }
            }
            .bottomActionBar {
                ExportActionBar(tab: options.tab, rendered: currentRender, isSaved: savedOutput == options.output,
                                walletAvailable: linkStatus.url != nil && services.network.isOnline,
                                walletAdded: wallet.addedCount > 0, isWalletLoading: wallet.isLoading,
                                onSavePhoto: saveToPhotos, onSaveFiles: { isExportingPDF = true },
                                onAddToWallet: addToWallet)
            }
            .task(id: RenderKey(output: options.output, design: card.design, content: content)) {
                await render(content: content)
            }
        }
        .walletAddFlow(wallet)
        .fileExporter(isPresented: $isExportingPDF, item: pdfItem, contentTypes: [.pdf],
                      defaultFilename: rendered?.fileName, onCompletion: didExportPDF)
        .settingsAlert($settingsAlert)
        .alert("Couldn’t Save", isPresented: isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: successCount)
        .onDisappear { rendered?.discard() }
    }

    // MARK: Rendering

    /// A new render for the current options is on its way (the old one stays visible, dimmed).
    private var isRendering: Bool {
        guard let output = options.output else { return false }
        return rendered?.output != output && failedOutput != output
    }

    /// The render for the current options (nil while a new one is being made).
    private var currentRender: RenderedExport? {
        guard let rendered, rendered.output == options.output else { return nil }
        return rendered
    }

    private var pdfItem: ExportedPDF? {
        guard let currentRender, case .pdf = currentRender.output else { return nil }
        return ExportedPDF(data: currentRender.data)
    }

    private func render(content: CardFaceContent) async {
        guard let output = options.output else { return }
        // Let the spinner appear and coalesce quick option changes before the synchronous render.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        let fileName = ExportFileNaming.fileName(for: output, fullName: content.fullName, cardName: card.name)
        do {
            let result = try ExportRenderer.render(output, design: card.design, content: content, fileName: fileName)
            rendered?.discard()
            rendered = result
            failedOutput = nil
        } catch {
            failedOutput = output
            errorMessage = "The export couldn’t be created. Try again."
        }
    }

    // MARK: Actions

    private func saveToPhotos() {
        guard let export = currentRender else { return }
        Task {
            do {
                try await PhotoLibrarySaver.save(imageData: export.data)
                didSave(export.output, toast: export.output.isWallpaper ? "Wallpaper Saved" : "Saved to Photos")
            } catch PhotoLibrarySaver.Failure.accessDenied {
                settingsAlert = SettingsAlert(
                    title: "Allow Photos Access",
                    message: "Open iOS Settings › \(Brand.appName) › Photos and choose Add Photos Only to save your card.")
            } catch {
                errorMessage = "The image couldn’t be saved to Photos. Try again."
            }
        }
    }

    private func didExportPDF(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            if let output = currentRender?.output { didSave(output, toast: "Saved to Files") }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func didSave(_ output: ExportOutput, toast: String) {
        savedOutput = output
        successCount += 1
        router.showToast(toast, systemImage: "checkmark.circle")
    }

    private func addToWallet() {
        let cardID = card.id
        let provider = walletPassProvider
        Task { await wallet.start(cardID: cardID, provider: provider) }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// Re-render whenever the output, the design or the public content changes.
private struct RenderKey: Hashable {
    let output: ExportOutput?
    let design: CardDesign
    let content: CardFaceContent
}

extension ExportOutput {
    var isWallpaper: Bool {
        if case .lockScreen = self { return true }
        return false
    }
}
