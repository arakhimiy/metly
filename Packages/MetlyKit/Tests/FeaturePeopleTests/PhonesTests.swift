import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeaturePeople

@MainActor
struct PhonesTests {
    // MARK: Message / Call

    @Test func severalNumbersAreAllCallableWithTheirLabels() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context, phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                   LabeledPhone(label: .home, value: "no number")]
        let reach = PersonReach(person)
        #expect(reach.callablePhones.map(\.labeledValue) == ["Mobile · +998 90 123 45 67", "Work · +998 71 200 00 00"])
    }

    @Test func oneNumberCallsDirectly() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context, phone: "+998 90 123 45 67")
        #expect(PersonReach(person).callablePhones.count == 1)
        #expect(PersonReach(insertPerson("Nobody", in: context)).callablePhones.isEmpty)
    }

    @Test func messageUsesTheTelegramUsernameFirst() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, telegram: "@kamila.y", phone: "+998 90 123 45 67")
        let reach = PersonReach(person)
        #expect(reach.message == .telegram(.username("kamila.y")))
        #expect(!reach.messagesTelegramByPhone)
    }

    @Test func withoutAUsernameMessageOpensTelegramByTheMobileNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context, phone: "+998 71 200 00 00")
        person.phoneLabel = .work
        person.additionalPhones = [LabeledPhone(label: .mobile, value: "90 123-45-67")]
        let reach = PersonReach(person)
        #expect(reach.message == .telegram(.phone("998901234567")))
        #expect(reach.messagesTelegramByPhone)
        // Messages stays available next to Telegram, on the mobile number.
        #expect(reach.smsURL?.absoluteString == "sms:901234567")
    }

    @Test func aLandlineOnlyFallsBackToMessages() throws {
        let context = try makeContext()
        let person = insertPerson("Office", in: context, phone: "+998 71 200 00 00")
        #expect(PersonReach(person).message == .sms(URL(string: "sms:+998712000000")!))
        #expect(PersonReach(insertPerson("Nobody", in: context)).message == .none)
    }

    // MARK: Merge / undo keep every number

    @Test func mergingAShareBackAddsTheirNumbersOnce() throws {
        let context = try makeContext()
        let justMet = insertPerson("Dilnoza", in: context, phone: "+998 90 111 22 33")
        let web = insertPerson("Dilnoza Ergasheva", in: context, phone: "+998 (90) 111-22-33")
        web.phoneLabel = .mobile
        web.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]

        ShareBackMerger.merge(web, into: justMet, in: context)

        #expect(justMet.allPhones.map(\.labeledValue) == ["Mobile · +998 90 111 22 33", "Work · +998 71 200 00 00"])
        #expect(justMet.additionalPhones.allSatisfy { !$0.isPrimary })
    }

    @Test func mergingIntoARecordWithoutAPhoneTakesTheirPrimaryAndLabel() throws {
        let context = try makeContext()
        let justMet = insertPerson("Dilnoza", in: context)
        let web = insertPerson("Dilnoza Ergasheva", in: context, phone: "+998 71 200 00 00")
        web.phoneLabel = .work
        web.additionalPhones = [LabeledPhone(label: .mobile, value: "+998 90 111 22 33")]

        ShareBackMerger.merge(web, into: justMet, in: context)

        #expect(justMet.phone == "+998 71 200 00 00")
        #expect(justMet.phoneLabel == .work)
        #expect(justMet.additionalPhones.map(\.value) == ["+998 90 111 22 33"])
    }

    /// Undo re-creates a hard-deleted person from its DTO: labels and extra numbers must come back too.
    @Test func undoAfterAHardDeleteKeepsEveryNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 71 200 00 00")
        person.phoneLabel = .work
        person.additionalPhones = [LabeledPhone(label: .mobile, value: "+998 90 123 45 67")]
        try context.save()
        let id = person.id

        let undo = PeopleActions.remove(person, in: context)
        context.delete(person)
        try context.save()
        undo()

        let restored = try #require(context.record(Connection.self, id: id))
        #expect(restored.phoneLabel == .work)
        #expect(restored.allPhones.map(\.labeledValue) == ["Work · +998 71 200 00 00", "Mobile · +998 90 123 45 67"])
    }
}
