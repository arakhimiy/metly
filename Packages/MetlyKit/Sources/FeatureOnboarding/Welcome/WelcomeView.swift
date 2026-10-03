import MetlyData
import MetlyDesign
import SwiftUI

/// ONB_WELCOME — 3-page value carousel (paged TabView, system page indicator).
struct WelcomeView: View {
    /// Skip / Get Started → AUTH_SIGNUP.
    let onFinish: () -> Void

    @State private var page: WelcomePage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialPage: WelcomePage = .share, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(WelcomePage.allCases) { item in
                WelcomePageView(page: item, isCurrent: item == page)
                    .tag(item)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        // A backing capsule keeps the white dots visible on the light background.
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground))
        .bottomActionBar {
            Button(action: advance) {
                Text(page.isLast ? "Get Started" : "Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
        .toolbar {
            if !page.isLast {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip", action: onFinish)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: page)
    }

    private func advance() {
        guard let next = page.next else {
            onFinish()
            return
        }
        withAnimation(reduceMotion ? nil : .smooth) {
            page = next
        }
    }
}

#Preview("Welcome · page 1") {
    NavigationStack { WelcomeView {} }
        .metlyPreview(.signedOut)
}

#Preview("Welcome · page 2") {
    NavigationStack { WelcomeView(initialPage: .context) {} }
        .metlyPreview(.signedOut)
}

#Preview("Welcome · page 3") {
    NavigationStack { WelcomeView(initialPage: .followUp) {} }
        .metlyPreview(.signedOut)
}

#Preview("Welcome · dark") {
    NavigationStack { WelcomeView(initialPage: .context) {} }
        .metlyPreview(.signedOut)
        .preferredColorScheme(.dark)
}

#Preview("Welcome · accessibility size") {
    NavigationStack { WelcomeView(initialPage: .followUp) {} }
        .metlyPreview(.signedOut)
        .dynamicTypeSize(.accessibility2)
}
