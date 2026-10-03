import SwiftUI

/// A toggleable capsule (tags, follow-up quick picks). Selected = bordered prominent, otherwise bordered.
/// Safe to place several in one List/Form row: bordered styles keep each chip individually tappable.
public struct CaptureChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Group {
            if isSelected {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var label: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.subheadline)
        // Keeps the hit target at 44 pt with the bordered style's own padding.
        .frame(minHeight: 30)
    }
}
