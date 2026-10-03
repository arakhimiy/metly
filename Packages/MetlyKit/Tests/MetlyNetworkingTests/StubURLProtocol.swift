import Foundation
import Synchronization
@testable import MetlyNetworking

/// Transport-level stub. Each test registers a handler for its own unique host, so tests can run
/// in parallel without sharing state.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, [String: String], Data)

    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func unregister(host: String) {
        handlers.withLock { $0[host] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var loadingTask: Task<Void, Never>?

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let request = request
        let box = ClientBox(client: client, owner: self)
        loadingTask = Task {
            do {
                let (status, headers, data) = try await handler(request)
                let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
                box.client?.urlProtocol(box.owner, didReceive: response, cacheStoragePolicy: .notAllowed)
                box.client?.urlProtocol(box.owner, didLoad: data)
                box.client?.urlProtocolDidFinishLoading(box.owner)
            } catch {
                box.client?.urlProtocol(box.owner, didFailWithError: error)
            }
        }
    }

    /// URLProtocolClient callbacks may be invoked from any thread (Foundation contract).
    private struct ClientBox: @unchecked Sendable {
        let client: (any URLProtocolClient)?
        let owner: URLProtocol
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}

/// A unique fake backend host + a client wired to it.
struct StubBackend {
    let host = "api-\(UUID().uuidString.lowercased()).metly.test"
    var baseURL: URL { URL(string: "https://\(host)")! }

    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func client(store: any SessionStore, retry: RetryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: .milliseconds(5), maxDelay: .milliseconds(20)),
                onInvalidated: @escaping @Sendable () -> Void = {}) -> APIClient {
        APIClient(baseURL: baseURL, sessionStore: store, urlSession: session(), retryPolicy: retry, appVersion: "test",
                  onSessionInvalidated: onInvalidated)
    }

    func handle(_ handler: @escaping StubURLProtocol.Handler) {
        StubURLProtocol.register(host: host, handler: handler)
    }
}

/// Thread-safe counters/recorders for assertions.
final class Recorder: Sendable {
    private let values = Mutex<[String: Int]>([:])
    private let strings = Mutex<[String: [String]]>([:])

    func increment(_ key: String) { values.withLock { $0[key, default: 0] += 1 } }
    func count(_ key: String) -> Int { values.withLock { $0[key, default: 0] } }
    func append(_ value: String, to key: String) { strings.withLock { $0[key, default: []].append(value) } }
    func list(_ key: String) -> [String] { strings.withLock { $0[key, default: []] } }
}

extension Data {
    static func json(_ value: some Encodable) -> Data { (try? MetlyJSON.makeEncoder().encode(value)) ?? Data() }
}

extension AuthSession {
    static func test(access: String = "old", refresh: String = "r-old", expiresIn: TimeInterval = 3600) -> AuthSession {
        AuthSession(userID: UUID(), email: "aziza@tezkor.uz", accessToken: access, refreshToken: refresh,
                    accessTokenExpiresAt: .now.addingTimeInterval(expiresIn))
    }
}
