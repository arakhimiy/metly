#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Runs `prepare` once against the preview store, then shows `content`.
struct HomePreviewPrepared<Content: View>: View {
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

/// Finds the first open reminder (after `prepare`), then shows `content(reminder)`.
struct HomePreviewReminder<Content: View>: View {
    var prepare: (ModelContext) -> Void = { _ in }
    let content: (FollowUp) -> Content

    @Environment(\.modelContext) private var modelContext
    @State private var reminder: FollowUp?

    var body: some View {
        Group {
            if let reminder {
                content(reminder)
            } else {
                ProgressView()
            }
        }
        .task {
            prepare(modelContext)
            try? modelContext.save()
            reminder = try? modelContext.fetch(FollowUp.open).first
        }
    }
}

/// Adjustments to `PreviewSeed` for the Home / Follow-ups states.
enum HomePreviewData {
    static func endActiveEvent(in context: ModelContext) {
        for event in (try? context.fetch(Event.active)) ?? [] {
            event.status = .ended
            event.endedAt = .now
        }
    }

    static func keepOnlyWorkCard(in context: ModelContext) {
        for card in (try? context.fetch(Card.live)) ?? [] where card.id != PreviewSeed.workCardID {
            card.markDeleted()
        }
    }

    static func makeWorkCardDraft(in context: ModelContext) {
        guard let card = context.record(Card.self, id: PreviewSeed.workCardID) else { return }
        card.publishState = .draft
        card.slug = ""
        card.stats = CardStats()
    }

    /// Moves every open reminder to later this week ("Nothing due today. N coming up.").
    static func nothingDueToday(in context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for (index, reminder) in ((try? context.fetch(FollowUp.open)) ?? []).enumerated() {
            let day = calendar.date(byAdding: .day, value: 2 + index, to: today) ?? today
            reminder.dueAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        }
    }

    /// Adds a "Later" reminder and a done one so every FOLLOWUPS group shows.
    static func addLaterAndDone(in context: ModelContext) {
        let people = (try? context.fetch(Connection.live)) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let madina = people.first(where: { $0.fullName.hasPrefix("Madina") }) {
            let due = calendar.date(byAdding: .day, value: 12, to: today).flatMap {
                calendar.date(bySettingHour: 10, minute: 0, second: 0, of: $0)
            } ?? .now
            let later = FollowUp(title: "Send the case study", channel: .email, dueAt: due)
            context.insert(later)
            later.connection = madina
        }
        if let timur = people.first(where: { $0.fullName.hasPrefix("Timur") }) {
            let done = FollowUp(title: "Coffee next week", channel: .telegram,
                                dueAt: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now)
            done.isDone = true
            done.completedAt = calendar.date(byAdding: .day, value: -1, to: .now)
            context.insert(done)
            done.connection = timur
        }
    }

    /// Tops the Free plan up to its 5 open reminders.
    static func fillToFreeLimit(in context: ModelContext) {
        let people = (try? context.fetch(Connection.live)) ?? []
        let open = (try? context.fetch(FollowUp.open)) ?? []
        for person in people.prefix(max(0, 5 - open.count)) {
            let reminder = FollowUp(title: "Follow up", channel: .telegram,
                                    dueAt: Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now)
            context.insert(reminder)
            reminder.connection = person
        }
    }
}
#endif
