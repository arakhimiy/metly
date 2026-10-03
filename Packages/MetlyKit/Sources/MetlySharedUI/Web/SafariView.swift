import SafariServices
import SwiftUI

/// In-app browser (`SFSafariViewController`) for the public card page, help and legal pages.
public struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    public init(url: URL, onFinish: @escaping () -> Void = {}) {
        self.url = url
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    public final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

/// Identifiable wrapper so a URL can drive `.fullScreenCover(item:)`.
public struct BrowserPage: Identifiable, Hashable {
    public let url: URL
    public var id: URL { url }
    public init(url: URL) { self.url = url }
}

public extension View {
    /// Presents `page` in `SafariView`, full screen as Safari View Controller expects.
    func inAppBrowser(_ page: Binding<BrowserPage?>) -> some View {
        fullScreenCover(item: page) { item in
            // Safari's Close button dismisses the controller itself; keep the binding in sync.
            SafariView(url: item.url) { page.wrappedValue = nil }
                .ignoresSafeArea()
        }
    }
}
