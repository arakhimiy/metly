import SwiftUI

/// Section header with an optional trailing action ("See All", "New Card", "Show").
/// Pair with `.headerProminence(.increased)` on Home.
struct HomeSectionHeader<Trailing: View>: View {
    let title: Text
    @ViewBuilder var trailing: Trailing

    init(_ title: Text, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
                .font(.subheadline)
                .textCase(nil)
        }
    }
}
