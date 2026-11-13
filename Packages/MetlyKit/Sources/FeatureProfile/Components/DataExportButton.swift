import MetlyCore
import SwiftUI

/// "Download My Data" — asks the server to email an export link (toast *Link sent to your email*).
struct DataExportButton: View {
    var title = String(localized: "Download My Data", bundle: .appStrings)
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Button(action: requestExport) {
            HStack {
                Text(title)
                Spacer()
                if isRequesting {
                    ProgressView()
                }
            }
        }
        .disabled(isRequesting)
        .alert("Couldn’t Request Your Data", isPresented: $isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func requestExport() {
        guard services.network.isOnline else {
            show(String(localized: "You’re offline. Connect to the internet and try again.", bundle: .appStrings))
            return
        }
        Task {
            isRequesting = true
            defer { isRequesting = false }
            do {
                try await services.auth.requestDataExport()
                router.showToast(String(localized: "Link sent to your email", bundle: .appStrings), systemImage: "envelope")
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private func show(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
