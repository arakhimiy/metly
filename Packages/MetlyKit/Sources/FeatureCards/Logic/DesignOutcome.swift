import MetlyCore

/// Result of asking `CardDesignRules` to change a design.
nonisolated enum DesignOutcome: Equatable, Sendable {
    /// The change is allowed; this is the new design (it may include forced side effects).
    case updated(CardDesign)
    /// Pro-only choice on the Free plan.
    case requiresPro(PaywallTrigger)
    /// Not possible for this card; the UI explains why inline.
    case blocked(DesignBlockReason)
}

nonisolated enum DesignBlockReason: Equatable, Sendable {
    /// The Gradient template always uses the gradient background.
    case gradientTemplateIsAlwaysGradient
    /// Private fields never appear on a card.
    case privateField
}
