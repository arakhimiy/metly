import SwiftUI

/// Symbol + title + subtitle at the top of AUTH_SIGNUP.
struct AuthHeader: View {
    let mode: AuthMode
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize = 64.0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.rectangle.stack.fill")
                .font(.system(size: symbolSize))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(mode.title)
                    .font(.largeTitle)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                Text(mode.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
