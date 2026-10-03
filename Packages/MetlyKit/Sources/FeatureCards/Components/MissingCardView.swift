import MetlyCore
import SwiftUI

/// Shown by a card modal whose card was deleted (e.g. on another device) while it was open.
struct MissingCardView: View {
    let title: String
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Card Unavailable", systemImage: "rectangle.on.rectangle.slash",
                                   description: Text("This card was deleted."))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: router.dismiss)
                    }
                }
        }
    }
}
