import Testing
@testable import FeatureCards

struct CardNamingTests {
    @Test func defaultNameSkipsUsedSuggestions() {
        #expect(CardNaming.defaultName(existing: []) == "Work")
        #expect(CardNaming.defaultName(existing: ["work"]) == "Personal")
        #expect(CardNaming.defaultName(existing: ["Work", "Personal"]) == "Conference")
        #expect(CardNaming.defaultName(existing: ["Work", "Personal", "Conference"]) == "Card 4")
        #expect(CardNaming.defaultName(existing: ["Work", "Personal", "Conference", "Card 5"]) == "Card 6")
    }

    @Test func copyNames() {
        #expect(CardNaming.copyName(for: "Work", existing: ["Work"]) == "Work Copy")
        #expect(CardNaming.copyName(for: "Work", existing: ["Work", "Work Copy"]) == "Work Copy 2")
        #expect(CardNaming.copyName(for: "Work Copy", existing: ["Work", "Work Copy"]) == "Work Copy 2")
        #expect(CardNaming.copyName(for: "Work Copy 2", existing: ["Work", "Work Copy", "Work Copy 2"]) == "Work Copy 3")
        #expect(CardNaming.copyName(for: "  ", existing: []) == "Card Copy")
        // "Copy" on its own is a real name, not a suffix.
        #expect(CardNaming.copyName(for: "Copy", existing: ["Copy"]) == "Copy Copy")
    }
}
