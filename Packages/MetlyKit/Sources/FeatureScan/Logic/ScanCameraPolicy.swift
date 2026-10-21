import MetlyCore

/// When SCAN's camera may run, and where its results are pushed.
enum ScanCameraPolicy {
    /// The camera (and QR detection) runs only while SCAN itself is on screen. `onDisappear`
    /// covers tab switches and pushes, but not a sheet or cover on top (a reminder from a
    /// notification, EVENT_ENDED, QR from a widget…) — those must stop the camera too.
    /// - Parameters:
    ///   - isVisible: SCAN's root is on screen (`onAppear` / `onDisappear`).
    ///   - presentations: the router's sheets and covers.
    static func isCameraActive(isVisible: Bool, presentations: [Presentation]) -> Bool {
        isVisible && presentations.isEmpty
    }

    /// Pushes a scan result (SCANNED_CARD, PAPER_REVIEW) onto the Scan tab — reading a paper card
    /// takes a moment, and the user may have switched tabs meanwhile.
    static func show(_ destination: PushDestination, router: AppRouter) {
        router.paths[.scan, default: []].append(destination)
    }
}
