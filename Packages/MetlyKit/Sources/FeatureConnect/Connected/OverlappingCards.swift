import MetlyCardKit
import MetlyCore
import SwiftUI

/// Mine + theirs, fanned out like two cards just swapped (SPEC §2.5.27). They settle in with a
/// spring; with Reduce Motion they simply appear in place.
struct OverlappingCards: View {
    struct Face {
        var design: CardDesign
        var content: CardFaceContent
    }

    let mine: Face?
    let theirs: Face
    let accessibilityLabel: String

    @State private var isSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let mine {
                face(mine)
                    .rotationEffect(.degrees(isSettled ? -7 : 0))
                    .offset(x: isSettled ? -34 : 0, y: isSettled ? -12 : 0)
            }
            face(theirs)
                .rotationEffect(.degrees(isSettled ? 5 : 0))
                .offset(x: isSettled ? 34 : 0, y: isSettled ? 14 : 0)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear(perform: settle)
    }

    private func face(_ face: Face) -> some View {
        CardFaceView(design: face.design, content: face.content)
            .cardFaceElevation()
            .containerRelativeFrame(.horizontal) { length, _ in
                min(length * 0.58, 280)
            }
    }

    private func settle() {
        guard !isSettled else { return }
        if reduceMotion {
            isSettled = true
        } else {
            withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.15)) {
                isSettled = true
            }
        }
    }
}
