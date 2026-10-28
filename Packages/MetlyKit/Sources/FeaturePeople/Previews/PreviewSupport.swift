#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Sync stand-in that reports `.syncing` (People loading skeleton).
@MainActor
final class SyncingPreviewStub: SyncServicing {
    var status: SyncStatus = .syncing
    var lastSyncedAt: Date?
    func requestSync() {}
    func syncNow() async {}
}

/// Runs `prepare` once against the preview store, then shows `content`.
struct PreviewPrepared<Content: View>: View {
    var prepare: (ModelContext) -> Void
    @ViewBuilder var content: Content

    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                content
            } else {
                ProgressView()
            }
        }
        .task {
            prepare(modelContext)
            try? modelContext.save()
            isReady = true
        }
    }
}

/// Finds a seeded person by name (optionally adjusting them), then shows `content(id)`.
struct PreviewPerson<Content: View>: View {
    let name: String
    var prepare: (Connection, ModelContext) -> Void = { _, _ in }
    let content: (UUID) -> Content

    @Environment(\.modelContext) private var modelContext
    @State private var personID: UUID?

    var body: some View {
        Group {
            if let personID {
                content(personID)
            } else {
                ProgressView()
            }
        }
        .task {
            let all = (try? modelContext.fetch(FetchDescriptor<Connection>())) ?? []
            guard let person = all.first(where: { $0.fullName == name }) else { return }
            prepare(person, modelContext)
            try? modelContext.save()
            personID = person.id
        }
    }
}

enum PreviewData {
    /// Adds a "Who did you just meet?" record matching Dilnoza's web share-back (same first name, today).
    static func addPendingJustMet(named name: String, in context: ModelContext) {
        let metAt = Calendar.current.date(byAdding: .minute, value: -50, to: .now) ?? .now
        let justMet = Connection(fullName: name, source: .justMet,
                                 context: MeetingContext(eventName: "Tashkent Tech Week", place: "Hyatt Regency",
                                                         city: "Tashkent", metAt: metAt))
        justMet.note = "Recruiter, hiring two product designers. Wants my portfolio."
        justMet.isPendingMerge = true
        context.insert(justMet)
    }

    /// Mobile + work + home numbers and no Telegram username.
    static func giveSeveralPhones(to person: Connection) {
        person.phone = "+998 90 123 45 67"
        person.phoneLabel = .mobile
        person.telegram = ""
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 200 00 00"),
                                   LabeledPhone(label: .home, value: "+998 66 233 00 00")]
    }
}
#endif
