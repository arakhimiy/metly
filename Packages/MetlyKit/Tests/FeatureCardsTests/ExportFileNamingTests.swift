import MetlyCardKit
import MetlyCore
import Testing
@testable import FeatureCards

struct ExportFileNamingTests {
    @Test func fileNamesPerOutput() {
        let name = "Aziza Karimova", card = "Work"
        #expect(ExportFileNaming.fileName(for: .png(scale: .x2, corners: .rounded), fullName: name, cardName: card)
                == "Aziza Karimova - Work Card@2x.png")
        #expect(ExportFileNaming.fileName(for: .png(scale: .x3, corners: .square), fullName: name, cardName: card)
                == "Aziza Karimova - Work Card Square@3x.png")
        #expect(ExportFileNaming.fileName(for: .pdf(.single), fullName: name, cardName: card)
                == "Aziza Karimova - Work Card (Print).pdf")
        #expect(ExportFileNaming.fileName(for: .pdf(.sheetA4), fullName: name, cardName: card)
                == "Aziza Karimova - Work Card (A4 Sheet).pdf")
        #expect(ExportFileNaming.fileName(for: .lockScreen(.iPhoneSE), fullName: name, cardName: card)
                == "Aziza Karimova - Work Card Lock Screen (iPhone SE).png")
    }

    @Test func cardNamesEndingInCardAreNotDoubled() {
        #expect(ExportFileNaming.baseName(fullName: "Timur", cardName: "Business Card") == "Timur - Business Card")
    }

    @Test func unsafeCharactersAreRemoved() {
        #expect(ExportFileNaming.baseName(fullName: "A/B: C*D?", cardName: "Work\nNew") == "A B C D - Work New Card")
        #expect(ExportFileNaming.sanitize("..hidden") == "hidden")
        #expect(ExportFileNaming.sanitize("  many   spaces  ") == "many spaces")
    }

    @Test func fallbacks() {
        #expect(ExportFileNaming.baseName(fullName: "", cardName: "Work") == "Work Card")
        #expect(ExportFileNaming.baseName(fullName: "Aziza", cardName: " ") == "Aziza Card")
        #expect(ExportFileNaming.baseName(fullName: "///", cardName: "") == "Nameshake Card")
    }

    @Test func longNamesAreTruncated() {
        let base = ExportFileNaming.baseName(fullName: String(repeating: "Alexandrina ", count: 12), cardName: "Work")
        #expect(base.count <= ExportFileNaming.maximumBaseLength)
        #expect(!base.hasSuffix(" "))
    }

    @Test func outputTypesAndTabs() {
        #expect(ExportOutput.pdf(.single).contentType == .pdf)
        #expect(ExportOutput.png(scale: .x1, corners: .rounded).isPhoto)
        #expect(ExportOutput.lockScreen(.iPhone16Pro).tab == .lockScreen)
        #expect(ExportScale.x3.subtitle == "3060 × 1980 px · Print-ready")
    }

    @Test func optionsMapToOutputs() {
        var options = ExportOptions(tab: .image)
        options.scale = .x1
        options.corners = .square
        #expect(options.output == .png(scale: .x1, corners: .square))
        options.tab = .pdf
        #expect(options.output == .pdf(.single))
        options.tab = .wallet
        #expect(options.output == nil)   // the server signs passes
        options.tab = .lockScreen
        #expect(options.output == .lockScreen(.iPhone16Pro))
    }
}
