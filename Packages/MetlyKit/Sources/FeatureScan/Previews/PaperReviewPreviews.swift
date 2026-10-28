#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// PAPER_REVIEW states (SPEC Appendix A: 32 Paper card review, 33 → "Enter Manually").

#Preview("Paper · full") {
    let scan = ScanSamples.paperScan
    NavigationStack { PaperReviewScreen(draft: scan.draft, scan: scan) }
        .metlyPreview(.full)
}

#Preview("Paper · brand above the name") {
    let scan = ScanSamples.brandFirstScan
    NavigationStack { PaperReviewScreen(draft: scan.draft, scan: scan) }
        .metlyPreview(.full)
}

#Preview("Paper · sparse") {
    NavigationStack {
        PaperReviewView(draft: PaperCardParser.parse(text: ["Madina Alieva", "+998 90 000 11 22"]))
    }
    .metlyPreview(.full)
}

#Preview("Paper · entered manually") {
    let draft = PaperCardDraft(imageData: ScanSamples.sampleCardImage)
    NavigationStack {
        PaperReviewScreen(draft: draft, scan: PaperScan(draft: draft, recognizedText: ["TEZKOR", "D1lsh0d R@khimov"]))
    }
    .metlyPreview(.full)
}

#Preview("Paper · manual, no photo") {
    NavigationStack { PaperReviewView(draft: PaperCardDraft()) }
        .metlyPreview(.empty)
}

#Preview("Paper · already in People") {
    NavigationStack {
        PaperReviewView(draft: PaperCardDraft(fullName: "Kamila Yusupova", company: "Uzum",
                                              fields: [ContactField(kind: .telegram, value: "@kamila.y")]))
    }
    .metlyPreview(.full)
}

#Preview("Paper · dark, large type") {
    let scan = ScanSamples.paperScan
    NavigationStack { PaperReviewScreen(draft: scan.draft, scan: scan) }
        .metlyPreview(.full, plan: .pro)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility1)
}
#endif
