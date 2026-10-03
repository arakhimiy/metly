import MetlyCore
import MetlyData
import SwiftUI

/// Block {first} · Remove Connection — both confirmed with SPEC alerts.
struct DangerZoneSection: View {
    let person: Connection

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingBlock = false
    @State private var isConfirmingRemove = false

    private var firstName: String { PersonName.first(person.fullName) }

    var body: some View {
        Section {
            Button("Block \(firstName)", systemImage: "hand.raised", role: .destructive) {
                isConfirmingBlock = true
            }
            .alert("Block \(firstName)?", isPresented: $isConfirmingBlock) {
                Button("Cancel", role: .cancel) {}
                Button("Block", role: .destructive, action: block)
            } message: {
                Text("Your cards will look like they don’t exist to them.")
            }

            Button("Remove Connection", systemImage: "trash", role: .destructive) {
                isConfirmingRemove = true
            }
            .alert("Remove \(firstName)?", isPresented: $isConfirmingRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive, action: remove)
            } message: {
                Text("Your note will be deleted. They keep the card you shared.")
            }
        }
    }

    private func block() {
        PeopleActions.block(person, in: modelContext)
        router.pop()
        router.showToast("Blocked", systemImage: "hand.raised")
    }

    private func remove() {
        let undo = PeopleActions.remove(person, in: modelContext)
        router.pop()
        router.showToast("Connection Removed", systemImage: "trash", undo: undo)
    }
}
