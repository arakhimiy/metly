import Foundation
import Testing
@testable import MetlyCore

@Test func cardURLRoundTrip() {
    let url = Brand.cardURL(slug: "aziza-w7k2")
    #expect(url.absoluteString == "https://metly.link/c/aziza-w7k2")
    #expect(Brand.slug(from: url) == "aziza-w7k2")
}

@Test func publicAudienceHidesConnectionsFields() {
    #expect(CardAudience.public.allows(.public))
    #expect(!CardAudience.public.allows(.connections))
    #expect(!CardAudience.connections.allows(.private))
}

@Test func freePlanLimits() {
    #expect(PlanLimits.free.allows(count: 1, of: \.maxCards))
    #expect(!PlanLimits.free.allows(count: 2, of: \.maxCards))
    #expect(PlanLimits.pro.allows(count: 99, of: \.maxCards))
}
