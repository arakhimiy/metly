import SwiftUI

/// Thin wizard progress under the navigation bar.
struct CreateProgressBar: View {
    let value: Double

    var body: some View {
        ProgressView(value: value)
            .progressViewStyle(.linear)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .accessibilityLabel(Text("Progress"))
            .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}

extension View {
    /// Pins the wizard progress bar above the step's content.
    func createProgress(_ value: Double) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            CreateProgressBar(value: value)
        }
    }
}
