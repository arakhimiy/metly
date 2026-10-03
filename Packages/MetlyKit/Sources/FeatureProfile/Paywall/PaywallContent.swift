import Foundation
import MetlyCore

/// One "what you get" row on the paywall.
nonisolated struct PaywallBenefit: Identifiable, Equatable, Sendable {
    enum Kind: CaseIterable, Sendable {
        case cards, followUps, events, designs, eventExport
    }

    var kind: Kind
    var title: String
    var detail: String
    var symbolName: String

    var id: Kind { kind }

    static func make(_ kind: Kind) -> PaywallBenefit {
        switch kind {
        case .cards:
            PaywallBenefit(kind: kind, title: "Unlimited cards", detail: "Free: 2 cards", symbolName: "rectangle.stack.fill")
        case .followUps:
            PaywallBenefit(kind: kind, title: "Unlimited follow-up reminders", detail: "Free: 5 active", symbolName: "bell.badge.fill")
        case .events:
            PaywallBenefit(kind: kind, title: "Several events at once", detail: "Free: 1 active event", symbolName: "calendar")
        case .designs:
            PaywallBenefit(kind: kind, title: "Every template and palette", detail: "Editorial, Ocean, Ember and more", symbolName: "paintpalette.fill")
        case .eventExport:
            PaywallBenefit(kind: kind, title: "Export events to CSV", detail: "Every connection, note and follow-up", symbolName: "tablecells.fill")
        }
    }
}

/// Marketing copy tailored to what sent the user to the paywall (SPEC §2.5.37, §3.19).
nonisolated struct PaywallContent: Equatable, Sendable {
    var headline: String
    var message: String
    var symbolName: String
    /// The benefit the trigger is about; listed first.
    var highlighted: PaywallBenefit.Kind?
    var benefits: [PaywallBenefit]

    init(trigger: PaywallTrigger) {
        switch trigger {
        case .settings:
            headline = Brand.proName
            message = "Remember everyone you meet and follow up on time."
            symbolName = "crown.fill"
            highlighted = nil
        case .cardLimit:
            headline = "Unlimited Cards"
            message = "The Free plan includes 2 cards. Upgrade for a card for every side of your work."
            symbolName = "rectangle.stack.fill"
            highlighted = .cards
        case .followUpLimit:
            headline = "Unlimited Follow-ups"
            message = "The Free plan includes 5 active reminders. Upgrade and never lose track of a promise."
            symbolName = "bell.badge.fill"
            highlighted = .followUps
        case .eventLimit:
            headline = "Run Several Events"
            message = "The Free plan includes 1 active event. Upgrade to run several at once, each with its own summary."
            symbolName = "calendar"
            highlighted = .events
        case .proTemplate:
            headline = "Unlock Editorial"
            message = "Upgrade to use the Editorial template and every palette."
            symbolName = "paintpalette.fill"
            highlighted = .designs
        case .proPalette:
            headline = "Unlock Every Palette"
            message = "Upgrade to use Ocean, Ember and the Editorial template."
            symbolName = "paintpalette.fill"
            highlighted = .designs
        case .eventExport:
            headline = "Export Your Events"
            message = "Take every connection, note and follow-up with you as a CSV file."
            symbolName = "tablecells.fill"
            highlighted = .eventExport
        }
        benefits = Self.orderedBenefits(highlighting: highlighted)
    }

    static func orderedBenefits(highlighting highlighted: PaywallBenefit.Kind?) -> [PaywallBenefit] {
        var kinds = PaywallBenefit.Kind.allCases
        if let highlighted, let index = kinds.firstIndex(of: highlighted) {
            kinds.remove(at: index)
            kinds.insert(highlighted, at: 0)
        }
        return kinds.map(PaywallBenefit.make)
    }

    static let renewalTerms = "Payment is charged to your Apple ID. Your subscription renews automatically until canceled. Cancel anytime in Settings at least 24 hours before renewal."
}

/// Yearly vs monthly comparison ("Save 44%").
nonisolated enum PaywallPricing {
    /// Whole-percent saving of paying yearly instead of 12 × monthly; nil when there's no saving.
    static func savingsPercent(yearly: Decimal, monthly: Decimal) -> Int? {
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else { return nil }
        let ratio = NSDecimalNumber(decimal: 1 - yearly / twelveMonths).doubleValue
        let percent = Int((ratio * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    /// Yearly price spread over 12 months.
    static func monthlyEquivalent(ofYearly yearly: Decimal) -> Decimal {
        yearly / 12
    }
}
