import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureConnect

@MainActor
struct ConnectedPhonesTests {
    @Test func extraNumbersAreListedWithThePrimaryFirst() throws {
        let context = ModelContext(try makeContainer())
        let person = Connection(fullName: "Kamila Yusupova", source: .nearby)
        person.phone = "+998 90 555 12 34"
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                   LabeledPhone(label: .home, value: " ")]
        context.insert(person)
        #expect(ConnectedPhones.rows(for: person).map(\.labeledValue)
                == ["Mobile · +998 90 555 12 34", "Work · +998 71 200 00 00"])
    }

    @Test func oneNumberStaysOnTheirCardOnly() throws {
        let context = ModelContext(try makeContainer())
        let single = Connection(fullName: "Aziz", source: .nearby)
        single.phone = "+998 90 555 12 34"
        context.insert(single)
        #expect(ConnectedPhones.rows(for: single).isEmpty)

        let none = Connection(fullName: "Nodir", source: .nearby)
        context.insert(none)
        #expect(ConnectedPhones.rows(for: none).isEmpty)
    }

    @Test func addToContactsSavesEveryNumber() throws {
        let context = ModelContext(try makeContainer())
        let person = Connection(fullName: "Kamila Yusupova", source: .nearby)
        person.phone = "+998 90 555 12 34"
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]
        context.insert(person)
        #expect(ContactDraft(connection: person).phones.map(\.label) == [.mobile, .work])
    }
}
