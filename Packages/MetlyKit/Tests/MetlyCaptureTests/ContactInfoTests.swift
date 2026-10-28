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

    @Test func editingStartsFromTheWholeList() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, email: "k@uzum.uz", phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]
        person.contacts.append(ContactEntry(kind: .instagram, value: "@kamila"))
        let draft = ContactInfoDraft(connection: person)
        #expect(draft.entries.map(\.kind) == [.phone, .phone, .email, .instagram])
        #expect(draft.entries.compactMap(\.label) == [.mobile, .work])
        #expect(draft.nextPhoneLabel == .home)
    }

    @Test func addingReusesAnEmptyRowAndPicksTheNextFreeLabel() {
        var draft = ContactInfoDraft()
        let first = draft.add(.phone)
        // Tapping "+ Add Contact" again while the row is still empty moves to it, as another kind if asked.
        #expect(draft.add(.telegram) == first)
        #expect(draft.entries.map(\.kind) == [.telegram])
        draft.entries[0].value = "@kamila"
        draft.add(.phone)
        draft.entries[1].value = "90 111 11 11"
        draft.add(.phone)
        #expect(draft.entries.compactMap(\.label) == [.mobile, .work])
        draft.remove(id: draft.entries[1].id)
        #expect(draft.entries.map(\.kind) == [.telegram, .phone])
        draft.remove(atOffsets: [0])
        #expect(draft.entries.map(\.kind) == [.phone])
    }

    @Test func applyWritesTheCleanedList() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 90 123 45 67")
        person.syncState = .synced
        var draft = ContactInfoDraft(connection: person)
        draft.entries[0].label = .work
        let added = draft.add(.phone)!
        draft.entries[draft.entries.firstIndex { $0.id == added }!].value = "  +998   99 000 00 00 "
        let telegram = draft.add(.telegram)!
        draft.entries[draft.entries.firstIndex { $0.id == telegram }!].value = "t.me/kamila_y"
        draft.add(.whatsapp)   // left empty: dropped

        #expect(draft.apply(to: person))
        #expect(person.contacts.map(\.kind) == [.phone, .phone, .telegram])
        #expect(person.phone == "+998 90 123 45 67")
        #expect(person.phoneLabel == .work)
        #expect(person.additionalPhones.map(\.value) == ["+998 99 000 00 00"])
        #expect(person.telegram == "@kamila_y")
        #expect(person.syncState == .pendingUpsert)
    }

    @Test func deletingTheFirstNumberPromotesTheNextOne() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 90 123 45 67")
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00")]
        var draft = ContactInfoDraft(connection: person)
        draft.remove(atOffsets: [0])
        draft.apply(to: person)
        #expect(person.phone == "+998 71 200 00 00")
        #expect(person.phoneLabel == .work)
        #expect(person.additionalPhones.isEmpty)

        var cleared = ContactInfoDraft(connection: person)
        cleared.entries.removeAll()
        cleared.apply(to: person)
        #expect(person.phone.isEmpty)
        #expect(person.allPhones.isEmpty)
    }

    @Test func applyWithoutChangesDoesNotQueueASync() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, email: "k@uzum.uz", phone: "+998 90 123 45 67")
        person.syncState = .synced
        #expect(!ContactInfoDraft(connection: person).apply(to: person))
        #expect(person.syncState == .synced)
    }

    @Test func theListStaysWithinTheServerLimits() {
        var draft = ContactInfoDraft()
        for index in 0..<ContactEntry.maxCount {
            let id = draft.add(.phone)!
            draft.entries[draft.entries.firstIndex { $0.id == id }!].value = "90 000 00 \(index)"
        }
        #expect(!draft.canAdd)
        #expect(draft.add(.email) == nil)
        draft.entries[1].value = String(repeating: "1", count: 60)
        #expect(draft.savedEntries[1].value.count == LabeledPhone.maxValueLength)
        #expect(draft.savedEntries.count == ContactEntry.maxCount)
    }

    @Test func theDraftSuggestsAChannelFromItsValues() {
        let work = ContactEntry(kind: .phone, label: .work, value: "+998 71 200 00 00")
        let mobile = ContactEntry(kind: .phone, label: .mobile, value: "90 123 45 67")
        #expect(ContactInfoDraft(entries: [work]).preferredChannel == .call)
        #expect(ContactInfoDraft(entries: [work, mobile]).preferredChannel == .telegram)
        #expect(ContactInfoDraft(entries: [ContactEntry(kind: .email, value: "a@b.c")]).preferredChannel == .email)
    }
}
