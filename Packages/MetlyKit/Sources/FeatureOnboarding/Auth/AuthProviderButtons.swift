import AuthenticationServices
import SwiftUI
import UIKit

/// "Continue with Apple" (black, per Apple's button guidelines), then "Continue with Google" and
/// "Continue with Telegram" (subtle grey fill). All are flat, solid buttons — no Liquid Glass — of the same height and shape, with the Apple and Google
/// marks drawn at the same size. The Apple button is a custom one so its logo can match the Google "G";
/// it drives `ASAuthorizationController` itself and reports through the same request/completion closures
/// as `SignInWithAppleButton`.
struct AuthProviderButtons: View {
    let mode: AuthMode
    let onAppleRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onAppleCompletion: (Result<ASAuthorization, any Error>) -> Void
    let onGoogle: () -> Void
    let onTelegram: () -> Void

    @State private var apple = AppleSignInCoordinator()
    @ScaledMetric(relativeTo: .body) private var scaledLogoSize: CGFloat = 22
    /// Grows with Dynamic Type, but stops at 32 pt so the marks never outweigh the title.
    private var logoSize: CGFloat { min(scaledLogoSize, 32) }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                apple.start(onRequest: onAppleRequest, onCompletion: onAppleCompletion)
            } label: {
                AuthProviderLabel(title: mode.appleTitle) {
                    Image(systemName: "apple.logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .accessibilityHidden(true)   // the title already says "Apple"
                }
            }
            .buttonStyle(AuthProviderButtonStyle(kind: .apple))

            Button(action: onGoogle) {
                AuthProviderLabel(title: mode.googleTitle) {
                    GoogleLogo().frame(width: logoSize, height: logoSize)
                }
            }
            .buttonStyle(AuthProviderButtonStyle(kind: .subtle))

            Button(action: onTelegram) {
                AuthProviderLabel(title: mode.telegramTitle) {
                    TelegramLogo().frame(width: logoSize, height: logoSize)
                }
            }
            .buttonStyle(AuthProviderButtonStyle(kind: .subtle))
        }
    }
}

/// Logo + title, centred; the logo keeps a fixed slot so both buttons line up.
private struct AuthProviderLabel<Logo: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let logo: Logo

    var body: some View {
        HStack(spacing: 10) {
            logo
            Text(title)
                .multilineTextAlignment(.center)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
    }
}

/// Solid capsule (rounded rectangle before iOS 26, matching the system button shape), 50 pt tall,
/// growing with Dynamic Type.
private struct AuthProviderButtonStyle: ButtonStyle {
    enum Kind { case apple, subtle }
    let kind: Kind

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(kind == .apple ? Color.white : Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(background, in: shape)
            // A black button on a black (dark mode) screen needs an edge, as Apple's own black style has.
            .overlay {
                if kind == .apple, colorScheme == .dark {
                    shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        kind == .apple ? .black : Color(.secondarySystemFill)
    }

    /// Capsule, except when accessibility text sizes wrap the title onto several lines.
    private var shape: some InsettableShape {
        if dynamicTypeSize.isAccessibilitySize {
            AnyInsettableShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if #available(iOS 26, *) {
            AnyInsettableShape(Capsule())
        } else {
            AnyInsettableShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Type-erased `InsettableShape` (SwiftUI's `AnyShape` isn't insettable).
nonisolated private struct AnyInsettableShape: InsettableShape {
    private let base: @Sendable (CGRect, CGFloat) -> Path
    private var inset: CGFloat = 0

    init<S: InsettableShape>(_ shape: S) {
        base = { rect, amount in shape.inset(by: amount).path(in: rect) }
    }

    func path(in rect: CGRect) -> Path { base(rect, inset) }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// Runs the Sign in with Apple sheet for the custom button.
@Observable
final class AppleSignInCoordinator: NSObject {
    @ObservationIgnored private var controller: ASAuthorizationController?
    @ObservationIgnored private var onCompletion: ((Result<ASAuthorization, any Error>) -> Void)?

    func start(onRequest: (ASAuthorizationAppleIDRequest) -> Void,
               onCompletion: @escaping (Result<ASAuthorization, any Error>) -> Void) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        onRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.onCompletion = onCompletion
        controller.performRequests()
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        onCompletion?(result)
        onCompletion = nil
        controller = nil
    }
}

extension AppleSignInCoordinator: @preconcurrency ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(.failure(error))
    }
}

extension AppleSignInCoordinator: @preconcurrency ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window ?? ASPresentationAnchor()
    }
}

#Preview("Auth buttons · sign up") {
    AuthProviderButtons(mode: .signUp, onAppleRequest: { _ in }, onAppleCompletion: { _ in }, onGoogle: {}, onTelegram: {})
        .padding()
}
