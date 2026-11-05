import SwiftUI

/// Corner brackets (square for QR, card-shaped for paper) with a slow scan line.
/// Decorative: the hint pill below says what to do.
struct ViewfinderGuide: View {
    let mode: ScanMode
    /// The corners' frame on screen (global), without the padding around them.
    var onFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSweeping = false

    var body: some View {
        ViewfinderCorners()
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .overlay {
                if !reduceMotion {
                    ScanLine()
                        .frame(maxHeight: .infinity, alignment: isSweeping ? .bottom : .top)
                        .padding(12)
                        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isSweeping)
                }
            }
            .aspectRatio(mode.aspectRatio, contentMode: .fit)
            .frame(maxWidth: mode.maxGuideWidth)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrameChange($0) }
            .padding(.horizontal, 40)
            .shadow(color: .black.opacity(0.35), radius: 6)
            .animation(.smooth, value: mode)
            .onAppear { isSweeping = true }
            .accessibilityHidden(true)
    }
}

private struct ScanLine: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
            .frame(height: 2)
    }
}
