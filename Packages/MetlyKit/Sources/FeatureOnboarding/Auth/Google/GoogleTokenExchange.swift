import Foundation

nonisolated struct GoogleTokenResponse: Decodable, Equatable, Sendable {
    var idToken: String
    var accessToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
    }
}

private nonisolated struct GoogleTokenErrorResponse: Decodable {
    var error: String
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// Exchanges the authorization code at Google's token endpoint (no client secret: iOS client + PKCE).
nonisolated struct GoogleTokenExchange: Sendable {
    static let endpoint = URL(string: "https://oauth2.googleapis.com/token")!

    var configuration: GoogleOAuthConfiguration
    var session: URLSession = .shared

    static func request(code: String, verifier: String, configuration: GoogleOAuthConfiguration) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formEncoded([
            ("code", code),
            ("client_id", configuration.clientID),
            ("redirect_uri", configuration.redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", verifier),
        ])
        return request
    }

    /// `application/x-www-form-urlencoded`, escaping everything except RFC 3986 unreserved characters.
    static func formEncoded(_ pairs: [(String, String)]) -> Data {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escape(_ string: String) -> String {
            string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
        }
        let body = pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
        return Data(body.utf8)
    }

    func exchange(code: String, verifier: String) async throws -> GoogleTokenResponse {
        let request = Self.request(code: code, verifier: verifier, configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleSignInError.tokenExchangeFailed(nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data)
            throw GoogleSignInError.tokenExchangeFailed(failure?.errorDescription ?? failure?.error)
        }
        do {
            return try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        } catch {
            throw GoogleSignInError.invalidIDToken
        }
    }
}
