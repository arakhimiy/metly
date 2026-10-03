import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// DEFERRED_WELCOME — first launch after installing from someone's web card.
struct DeferredWelcomeScreen: View {
    let invite: DeferredInvite
    /// "Connect with {first}" → sign-in (the invite is surfaced after setup).
    let onConnect: () -> Void
    /// "Not Now" → regular onboarding.
    let onNotNow: () -> Void

    private var firstName: String {
        invite.ownerName.split(separator: " ").first.map(String.init) ?? invite.ownerName
    }

    private var title: LocalizedStringKey {
        if let event = invite.eventName, !event.isEmpty {
            "You met \(invite.ownerName) at \(event)."
        } else {
            "You met \(invite.ownerName)."
        }
    }

    var body: some View {
        FillOrScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 16)

                CardFaceView(design: invite.card.design, content: invite.card.faceContent)
                    .cardEdge()
                    .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.8, 380) }
                    .rotationEffect(.degrees(-3))
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                    .padding(.vertical, 8)

                VStack(spacing: 12) {
                    Text("Welcome to \(Brand.appName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.title)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                    Text("Create your account to save \(firstName)’s card and share yours back. It takes a minute.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 16)

                VStack(spacing: 8) {
                    Button(action: onConnect) {
                        Text("Connect with \(firstName)")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                    .controlSize(.large)

                    Button("Not Now", action: onNotNow)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}

#Preview("Deferred welcome") {
    NavigationStack {
        DeferredWelcomeScreen(invite: OnboardingSamples.invite, onConnect: {}, onNotNow: {})
    }
    .metlyPreview(.signedOut)
}

#Preview("Deferred welcome · no event, dark") {
    NavigationStack {
        DeferredWelcomeScreen(invite: OnboardingSamples.inviteWithoutEvent, onConnect: {}, onNotNow: {})
    }
    .metlyPreview(.signedOut)
    .preferredColorScheme(.dark)
}

#Preview("Deferred welcome · accessibility size") {
    NavigationStack {
        DeferredWelcomeScreen(invite: OnboardingSamples.invite, onConnect: {}, onNotNow: {})
    }
    .metlyPreview(.signedOut)
    .dynamicTypeSize(.accessibility3)
}
