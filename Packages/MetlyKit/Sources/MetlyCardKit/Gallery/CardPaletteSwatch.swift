import MetlyCore
import SwiftUI

/// Palette swatch for the editor's Color section: background/accent split circle, selection ring
/// and a lock for Pro palettes. At least 44 × 44 pt. Not a button — wrap it in one.
public struct CardPaletteSwatch: View {
    let palette: CardPalette
    let appearance: CardAppearance
    let isSelected: Bool
    let isLocked: Bool

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 34

    public init(palette: CardPalette, appearance: CardAppearance = .dark, isSelected: Bool = false, isLocked: Bool = false) {
        self.palette = palette
        self.appearance = appearance
        self.isSelected = isSelected
        self.isLocked = isLocked
    }

    public var body: some View {
        let colors = palette.colors(appearance)
        ZStack {
            Circle().fill(colors.background.color)
            // Filled half-circle (chord through the centre), rotated to a diagonal split.
            Circle()
                .trim(from: 0, to: 0.5)
                .fill(colors.accent.color)
                .rotationEffect(.degrees(-45))
            Circle().strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .frame(width: diameter, height: diameter)
        .padding(4)
        .overlay {
            Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .overlay(alignment: .bottomTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.background, in: .circle)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(palette.title))
        .accessibilityValue(isLocked ? Text("Requires \(Brand.proName)") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
