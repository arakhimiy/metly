import AuthenticationServices
import MetlyDesign
import SwiftUI

/// Native Sign in with Apple button + "Continue with Google" (SF Symbol + text, no Google logo asset).
struct AuthProviderButtons: View {
    let mode: AuthMode
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, any Error>) -> Void
    let onGoogle: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(mode.appleLabel, onRequest: onAppleRequest, onCompletion: onAppleCompletion)
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .modifier(AuthButtonClip())
                // The button doesn't restyle itself when the color scheme flips at runtime.
                .id(colorScheme)

            // Large control size + body text ≈ the Apple button's 50 pt; grows with Dynamic Type.
            Button(action: onGoogle) {
                Label(mode.googleTitle, systemImage: "g.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .secondaryButtonStyle()
            .controlSize(.large)
            .modifier(AuthButtonBorderShape())
        }
    }
}

/// Matches the Apple button's corners to the system button shape (capsule on iOS 26).
private struct AuthButtonClip: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.clipShape(.capsule)
        } else {
            content.clipShape(.rect(cornerRadius: 12))
        }
    }
}

private struct AuthButtonBorderShape: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonBorderShape(.capsule)
        } else {
            content.buttonBorderShape(.roundedRectangle(radius: 12))
        }
    }
}
