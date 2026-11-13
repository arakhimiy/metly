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
            PaywallBenefit(kind: kind, title: String(localized: "Unlimited cards", bundle: .appStrings), detail: String(localized: "Free: 2 cards", bundle: .appStrings), symbolName: "rectangle.stack.fill")
        case .followUps:
            PaywallBenefit(kind: kind, title: String(localized: "Unlimited follow-up reminders", bundle: .appStrings), detail: String(localized: "Free: 5 active", bundle: .appStrings), symbolName: "bell.badge.fill")
        case .events:
            PaywallBenefit(kind: kind, title: String(localized: "Several events at once", bundle: .appStrings), detail: String(localized: "Free: 1 active event", bundle: .appStrings), symbolName: "calendar")
        case .designs:
            PaywallBenefit(kind: kind, title: String(localized: "Every template and palette", bundle: .appStrings), detail: String(localized: "Foil, Aurora, Editorial and every palette", bundle: .appStrings), symbolName: "paintpalette.fill")
        case .eventExport:
            PaywallBenefit(kind: kind, title: String(localized: "Export events to CSV", bundle: .appStrings), detail: String(localized: "Every connection, note and follow-up", bundle: .appStrings), symbolName: "tablecells.fill")
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
            message = String(localized: "Remember everyone you meet and follow up on time.", bundle: .appStrings)
            symbolName = "crown.fill"
            highlighted = nil
        case .cardLimit:
            headline = String(localized: "Unlimited Cards", bundle: .appStrings)
            message = String(localized: "The Free plan includes 2 cards. Upgrade for unlimited cards.", bundle: .appStrings)
            symbolName = "rectangle.stack.fill"
            highlighted = .cards
        case .followUpLimit:
            headline = String(localized: "Unlimited Follow-ups", bundle: .appStrings)
            message = String(localized: "The Free plan includes 5 active reminders. Upgrade for unlimited reminders.", bundle: .appStrings)
            symbolName = "bell.badge.fill"
            highlighted = .followUps
        case .eventLimit:
            headline = String(localized: "Run Several Events", bundle: .appStrings)
            message = String(localized: "The Free plan includes 1 active event. Upgrade to run several at once, each with its own summary.", bundle: .appStrings)
            symbolName = "calendar"
            highlighted = .events
        case .proTemplate:
            headline = String(localized: "Unlock Pro Templates", bundle: .appStrings)
            message = String(localized: "Upgrade to use Foil, Aurora, Editorial and every palette.", bundle: .appStrings)
            symbolName = "paintpalette.fill"
            highlighted = .designs
        case .proPalette:
            headline = String(localized: "Unlock Every Palette", bundle: .appStrings)
            message = String(localized: "Upgrade to use Ocean, Ember and the Foil, Aurora and Editorial templates.", bundle: .appStrings)
            symbolName = "paintpalette.fill"
            highlighted = .designs
        case .eventExport:
            headline = String(localized: "Export Your Events", bundle: .appStrings)
            message = String(localized: "Take every connection, note and follow-up with you as a CSV file.", bundle: .appStrings)
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

    static var renewalTerms: String { String(localized: "Payment is charged to your Apple ID. Your subscription renews automatically until canceled. Cancel anytime in Settings at least 24 hours before renewal.", bundle: .appStrings) }
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
