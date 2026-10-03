import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Resolves the routed IDs to models, then shows REMINDER_EDIT (or a "not found" state when the
/// reminder was deleted meanwhile, e.g. from another device).
struct ReminderEditLoader: View {
    let followUpID: UUID?
    let connectionID: UUID?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let existing = followUpID.flatMap { modelContext.record(FollowUp.self, id: $0) }.flatMap { $0.isDeleted ? nil : $0 }
        if followUpID != nil, existing == nil {
            ReminderMissingView()
        } else {
            let person = existing?.connection ?? connectionID.flatMap { modelContext.record(Connection.self, id: $0) }
            ReminderEditScreen(existing: existing, person: person, isPersonFixed: existing != nil || person != nil)
        }
    }
}

private struct ReminderMissingView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Reminder Not Found", systemImage: "bell.slash",
                                   description: Text("It may have been deleted on another device."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: close)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private func close() {
        router.dismiss()
    }
}
