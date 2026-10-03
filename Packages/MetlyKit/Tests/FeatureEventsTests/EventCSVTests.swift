import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureEvents

@MainActor
struct EventCSVTests {
    // MARK: Escaping

    @Test(arguments: [
        ("Kamila", "Kamila"),
        ("Uzum, Market", "\"Uzum, Market\""),
        ("The \"best\" deck", "\"The \"\"best\"\" deck\""),
        ("Line one\nLine two", "\"Line one\nLine two\""),
        ("Windows\r\nbreak", "\"Windows\r\nbreak\""),
        (" padded ", "\" padded \""),
        ("", ""),
    ])
    func escapesFieldsPerRFC4180(input: String, expected: String) {
        #expect(EventCSV.escape(input) == expected)
    }

    @Test func formulaLikeValuesAreNeutralized() {
        #expect(EventCSV.field("=HYPERLINK(\"http://x\")") == "\"'=HYPERLINK(\"\"http://x\"\")\"")
        #expect(EventCSV.field("@kamila.y") == "'@kamila.y")
        #expect(EventCSV.field("+cmd|' /C calc'!A0") == "'+cmd|' /C calc'!A0")
        #expect(EventCSV.field("-2+3+cmd") == "'-2+3+cmd")
    }

    @Test func phoneNumbersAreLeftAlone() {
        #expect(EventCSV.field("+998 90 123 45 67") == "+998 90 123 45 67")
        #expect(EventCSV.field("+1 (415) 555-0100") == "+1 (415) 555-0100")
        #expect(EventCSV.field("Telegram") == "Telegram")
    }

    // MARK: Document

    @Test func documentHasHeaderRowsAndCRLF() {
        let rows = [
            EventCSVRow(values: [.name: "Kamila Yusupova", .company: "Uzum", .note: "Send the deck, today"]),
            EventCSVRow(values: [.name: "Sardor", .company: "Payme"]),
        ]
        let text = EventCSV.text(rows: rows, columns: [.name, .company, .note])
        #expect(text == "Name,Company,Note\r\nKamila Yusupova,Uzum,\"Send the deck, today\"\r\nSardor,Payme,\r\n")
    }

    @Test func columnsFollowFileOrderAndAlwaysIncludeName() {
        let rows = [EventCSVRow(values: [.name: "Kamila", .email: "k@uzum.uz", .phone: "+998 90 000 00 00"])]
        let text = EventCSV.text(rows: rows, columns: [.email, .phone])
        #expect(text.hasPrefix("Name,Phone,Email\r\n"))
        #expect(EventCSVColumn.ordered([.tags, .name, .phone]) == [.name, .phone, .tags])
    }

    @Test func dataStartsWithUTF8ByteOrderMark() {
        let rows = [EventCSVRow(values: [.name: "Дилноза Эргашева"])]
        let data = EventCSV.data(rows: rows, columns: [.name])
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let decoded = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(decoded == "Name\r\nДилноза Эргашева\r\n")
    }

    @Test func allColumnsHaveHeaders() {
        let header = EventCSV.text(rows: [], columns: EventCSVColumn.allCases)
        #expect(header == "Name,Title,Company,Phone,Email,Telegram,Website,LinkedIn,Event,Met At,Place,Note,Tags,Follow-up\r\n")
    }

    // MARK: Rows from connections

    @Test func rowCarriesContactContextNoteTagsAndFollowUp() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let person = insertPerson("Kamila Yusupova", at: event, in: context, note: "Wants the pitch deck",
                                  telegram: "@kamila.y", email: "kamila@uzum.uz", phone: "+998 90 111 22 33",
                                  metAt: date(2026, 9, 25, 14, 5))
        person.jobTitle = "Head of Partnerships"
        person.company = "Uzum"
        person.tags = ["Investor", "Client"]
        let reminder = insertFollowUp(for: person, in: context, dueInDays: 1)
        reminder.title = "Send the pitch deck"
        reminder.dueAt = date(2026, 9, 27, 10, 0)

        let row = EventCSVRow(person: person, eventName: event.name, calendar: testCalendar)
        #expect(row[.name] == "Kamila Yusupova")
        #expect(row[.jobTitle] == "Head of Partnerships")
        #expect(row[.telegram] == "@kamila.y")
        #expect(row[.event] == "Tashkent Tech Week")
        #expect(row[.metAt] == "2026-09-25 14:05")
        #expect(row[.place] == "Hyatt Regency, Tashkent")
        #expect(row[.note] == "Wants the pitch deck")
        #expect(row[.tags] == "Investor, Client")
        #expect(row[.followUp] == "Send the pitch deck · 2026-09-27 10:00 · Telegram")
    }

    @Test func followUpColumnShowsDoneOrNothing() throws {
        let context = try makeContext()
        let done = insertPerson("Done Person", in: context)
        insertFollowUp(for: done, in: context, done: true)
        let none = insertPerson("No Reminder", in: context)
        #expect(EventCSVRow.followUpText(for: done, calendar: testCalendar) == "Done")
        #expect(EventCSVRow.followUpText(for: none, calendar: testCalendar) == "")
    }

    // MARK: File

    @Test func fileNameIsSafe() {
        #expect(EventCSV.fileName(for: "Tashkent Tech Week") == "Tashkent Tech Week.csv")
        #expect(EventCSV.fileName(for: "Q3/Q4: Review?") == "Q3Q4 Review.csv")
        #expect(EventCSV.fileName(for: "  ") == "Event.csv")
    }

    @Test func writesAFileWithTheExport() throws {
        let rows = [EventCSVRow(values: [.name: "Kamila"])]
        let url = try EventCSV.write(rows: rows, columns: [.name], eventName: "Test Export")
        defer { EventCSV.removeExports() }
        #expect(url.lastPathComponent == "Test Export.csv")
        #expect(try Data(contentsOf: url) == EventCSV.data(rows: rows, columns: [.name]))
    }
}
