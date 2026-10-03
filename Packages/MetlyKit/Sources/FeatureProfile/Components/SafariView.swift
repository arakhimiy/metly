import SafariServices
import SwiftUI

/// In-app browser (`SFSafariViewController`) for the public card page, help and legal pages.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

/// Identifiable wrapper so a URL can drive `.fullScreenCover(item:)`.
struct BrowserPage: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}

extension View {
    /// Presents `page` in `SafariView`, full screen as Safari View Controller expects.
    func inAppBrowser(_ page: Binding<BrowserPage?>) -> some View {
        fullScreenCover(item: page) { item in
            // Safari's Close button dismisses the controller itself; keep the binding in sync.
            SafariView(url: item.url) { page.wrappedValue = nil }
                .ignoresSafeArea()
        }
    }
}
