import Foundation
import MetlyCore
import SwiftData
import Testing
@testable import MetlyData

/// Card face content from the contact list.
@Suite("Card face content")
struct CardFaceContentTests {
    @Test("Card face content carries public extra phones only")
    func faceContentFiltersExtraPhones() throws {
        let profile = Profile(fullName: "Aziza", contactFields: [ContactField(kind: .phone, value: "+998 90 1", privacy: .public)])
        profile.additionalPhones = [
            LabeledPhone(label: .work, value: "+998 71 1", privacy: .public),
            LabeledPhone(label: .home, value: "+998 71 2", privacy: .connections),
            LabeledPhone(label: .other, value: "+998 71 3", privacy: .private),
        ]
        let card = Card(name: "Work")
        #expect(card.faceContent(profile: profile, audience: .public).additionalPhones.map(\.value) == ["+998 71 1"])
        #expect(card.faceContent(profile: profile, audience: .connections).additionalPhones.map(\.value) == ["+998 71 1", "+998 71 2"])
        card.design.visibleFields.remove(.phone)
        #expect(card.faceContent(profile: profile, audience: .connections).additionalPhones.isEmpty)
    }
}
