import MetlyCore

/// What PAPER_REVIEW shows besides the draft — the recognized text and which roles are sure —
/// for the few scans in flight. `PaperCardDraft` is the frozen `.paperReview` route payload and
/// can't carry them yet (see the contract change request in the Scan report); SCAN remembers
/// the scan right before pushing the route, PAPER_REVIEW looks it up by its draft.
@MainActor
enum PaperScanStore {
    private static var recent: [PaperScan] = []
    private static let capacity = 4

    static func remember(_ scan: PaperScan) {
        recent.removeAll { $0.draft == scan.draft }
        recent.append(scan)
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
    }

    static func scan(for draft: PaperCardDraft) -> PaperScan? {
        recent.last { $0.draft == draft }
    }
}
