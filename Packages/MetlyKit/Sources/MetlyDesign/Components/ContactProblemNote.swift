import SwiftUI

/// Red footnote under a contact value that isn't valid for its kind ("Enter an email address, like …").
public struct ContactProblemNote: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .accessibilityLabel(Text(text))
    }
}

#Preview {
    Form {
        ContactProblemNote("Enter an email address, like name@example.com.")
    }
}
