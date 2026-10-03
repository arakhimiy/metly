import AuthenticationServices
import Foundation
import MetlyCore

/// Maps Sign in with Apple results onto the `AuthServicing` contract.
enum AppleCredentialMapper {
    static func credential(from apple: ASAuthorizationAppleIDCredential) -> AppleSignInCredential {
        AppleSignInCredential(userID: apple.user,
                              identityToken: apple.identityToken,
                              authorizationCode: apple.authorizationCode,
                              fullName: nonEmpty(apple.fullName),
                              email: apple.email)
    }

    /// Apple sends an empty `PersonNameComponents` on every authorization after the first.
    nonisolated static func nonEmpty(_ name: PersonNameComponents?) -> PersonNameComponents? {
        guard let name else { return nil }
        let parts = [name.namePrefix, name.givenName, name.middleName, name.familyName, name.nameSuffix, name.nickname]
        return parts.contains { !($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty } ? name : nil
    }

    nonisolated static func displayName(_ name: PersonNameComponents?) -> String? {
        guard let name = nonEmpty(name) else { return nil }
        let formatted = name.formatted()
        return formatted.isEmpty ? nil : formatted
    }

    /// The identity token carries the (possibly private-relay) email even when `credential.email` is nil.
    nonisolated static func email(fromIdentityToken token: Data?) -> String? {
        guard let token, let jwt = String(data: token, encoding: .utf8) else { return nil }
        return IDTokenClaims.decode(jwt: jwt)?.email
    }

    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }
}
