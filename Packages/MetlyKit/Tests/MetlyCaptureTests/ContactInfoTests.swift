@preconcurrency import Contacts
import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import MetlyCapture

@MainActor
struct ContactInfoTests {
    // MARK: Saving to iOS Contacts

    @Test func everyPhoneIsSavedWithItsContactsLabel() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila Yusupova", in: context, phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                   LabeledPhone(label: .home, value: "+998 66 233 00 00"),
                                   LabeledPhone(label: .other, value: "+7 912 345-67-89"),
                                   LabeledPhone(label: .work, value: "  ")]
        let contact = ContactDraft(connection: person).makeContact()
        #expect(contact.phoneNumbers.map(\.label) == [CNLabelPhoneNumberMobile, CNLabelWork, CNLabelHome, CNLabelOther])
        #expect(contact.phoneNumbers.map(\.value.stringValue)
                == ["+998 90 123 45 67", "+998 71 200 00 00", "+998 66 233 00 00", "+7 912 345-67-89"])
    }

    @Test func theSameNumberIsSavedOnce() {
        let draft = ContactDraft(fullName: "Aziz", phone: "+998 90 123 45 67", phoneLabel: .work,
                                 additionalPhones: [LabeledPhone(label: .mobile, value: "+998 (90) 123-45-67")])
        let numbers = draft.makeContact().phoneNumbers
        #expect(numbers.count == 1)
        #expect(numbers.first?.label == CNLabelWork)
    }

    @Test func thePrimaryPhoneKeepsWorkingForSingleNumberCallers() {
        var draft = ContactDraft(fullName: "Aziz", phone: "90 123 45 67")
        #expect(draft.phone == "90 123 45 67")
        #expect(draft.phones.map(\.label) == [.mobile])
        draft.phone = "+998 91 000 00 00"
        #expect(draft.phones.map(\.value) == ["+998 91 000 00 00"])
        #expect(ContactDraft(fullName: "No Phone").makeContact().phoneNumbers.isEmpty)
    }

    // MARK: Editing

    @Test func editingStartsFromEveryPhone() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, email: "k@uzum.uz", phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]
        let draft = ContactInfoDraft(connection: person)
        #expect(draft.phones.map(\.label) == [.mobile, .work])
        #expect(draft.phones.first?.isPrimary == true)
        #expect(draft.email == "k@uzum.uz")
        #expect(draft.nextPhoneLabel == .home)
    }

    @Test func addingPhonesPicksTheNextFreeLabel() {
        var draft = ContactInfoDraft()
        #expect(draft.nextPhoneLabel == .mobile)
        draft.addPhone()
        draft.addPhone()
        draft.addPhone()
        draft.addPhone()
        draft.addPhone()
        #expect(draft.phones.map(\.label) == [.mobile, .work, .home, .other, .other])
        let second = draft.phones[1].id
        draft.removePhone(id: second)
        #expect(draft.phones.map(\.label) == [.mobile, .home, .other, .other])
        draft.removePhones(atOffsets: [0, 2])
        #expect(draft.phones.map(\.label) == [.home, .other])
    }

    @Test func applyWritesThePrimaryAndTheExtraPhones() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 90 123 45 67")
        person.syncState = .synced
        var draft = ContactInfoDraft(connection: person)
        draft.phones[0].label = .work
        let added = draft.addPhone()
        draft.phones[draft.phones.firstIndex { $0.id == added }!].value = "  +998   99 000 00 00 "
        draft.addPhone()   // left empty: dropped
        draft.telegram = "t.me/kamila_y"

        #expect(draft.apply(to: person))
        #expect(person.phone == "+998 90 123 45 67")
        #expect(person.phoneLabel == .work)
        #expect(person.additionalPhones.map(\.value) == ["+998 99 000 00 00"])
        #expect(person.additionalPhones.map(\.label) == [.mobile])
        #expect(person.telegram == "@kamila_y")
        #expect(person.syncState == .pendingUpsert)
    }

    @Test func deletingThePrimaryPromotesTheNextNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]
        var draft = ContactInfoDraft(connection: person)
        draft.removePhone(id: LabeledPhone.primaryID)
        draft.apply(to: person)
        #expect(person.phone == "+998 71 200 00 00")
        #expect(person.phoneLabel == .work)
        #expect(person.additionalPhones.isEmpty)
        #expect(person.allPhones.map(\.labeledValue) == ["Work · +998 71 200 00 00"])

        var cleared = ContactInfoDraft(connection: person)
        cleared.phones.removeAll()
        cleared.apply(to: person)
        #expect(person.phone.isEmpty)
        #expect(person.phoneLabel == .mobile)
        #expect(person.allPhones.isEmpty)
    }

    @Test func thePrimaryIDNeverLandsOnAnExtraNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context)
        let draft = ContactInfoDraft(phones: [LabeledPhone(label: .mobile, value: "90 111 11 11"),
                                              LabeledPhone(id: LabeledPhone.primaryID, label: .work, value: "71 200 00 00")])
        draft.apply(to: person)
        #expect(person.additionalPhones.count == 1)
        #expect(person.additionalPhones.allSatisfy { !$0.isPrimary })
    }

    @Test func applyWithoutChangesDoesNotQueueASync() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, email: "k@uzum.uz", phone: "+998 90 123 45 67")
        person.syncState = .synced
        #expect(!ContactInfoDraft(connection: person).apply(to: person))
        #expect(person.syncState == .synced)
    }

    @Test func theDraftSuggestsAChannelFromItsValues() {
        #expect(ContactInfoDraft(phones: [LabeledPhone(label: .work, value: "+998 71 200 00 00")]).preferredChannel == .call)
        #expect(ContactInfoDraft(phones: [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                          LabeledPhone(label: .mobile, value: "90 123 45 67")]).preferredChannel == .telegram)
        #expect(ContactInfoDraft(email: "a@b.c").preferredChannel == .email)
    }
}
