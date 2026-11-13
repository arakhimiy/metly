import Foundation
import Testing
@testable import MetlyNetworking

@Suite("APIClient")
struct APIClientTests {
    private struct Item: Codable, Sendable, Equatable { var value: String }

    private static func tokens(_ access: String, _ refresh: String) -> SessionTokens {
        SessionTokens(accessToken: access, refreshToken: refresh, accessTokenExpiresAt: .now.addingTimeInterval(3600))
    }

    @Test("Concurrent 401s share exactly one refresh, then every request is replayed")
    func singleFlightRefresh() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { request in
            if request.url?.path() == "/v1/auth/refresh" {
                recorder.increment("refresh")
                try await Task.sleep(for: .milliseconds(80))   // keep the refresh in flight while others pile up
                return (200, ["Content-Type": "application/json"], .json(Self.tokens("new", "r-new")))
            }
            let auth = request.value(forHTTPHeaderField: "Authorization")
            recorder.append(auth ?? "-", to: "auth")
            guard auth == "Bearer new" else {
                return (401, [:], .json(APIProblem(.tokenExpired, "Access token expired.")))
            }
            return (200, [:], .json(Item(value: "ok")))
        }
        let store = InMemorySessionStore(.test())
        let client = backend.client(store: store)

        let results = try await withThrowingTaskGroup(of: Item.self) { group in
            for _ in 0..<6 { group.addTask { try await client.send(Endpoint<Item>(.get, "/v1/me")) } }
            return try await group.reduce(into: [Item]()) { $0.append($1) }
        }

        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.value == "ok" })
        #expect(recorder.count("refresh") == 1)
        #expect(store.load()?.accessToken == "new")
        #expect(store.load()?.refreshToken == "r-new")
    }

    @Test("A rejected refresh token clears the session and reports .unauthorized")
    func refreshRejected() async throws {
        let backend = StubBackend()
        let invalidated = Recorder()
        backend.handle { request in
            if request.url?.path() == "/v1/auth/refresh" {
                return (401, [:], .json(APIProblem(.invalidGrant, "Refresh token revoked.")))
            }
            return (401, [:], Data())
        }
        let store = InMemorySessionStore(.test())
        let client = backend.client(store: store) { invalidated.increment("called") }

        await #expect(throws: APIError.unauthorized) {
            _ = try await client.send(Endpoint<Item>(.get, "/v1/me"))
        }
        #expect(store.load() == nil)
        #expect(invalidated.count("called") == 1)
    }

    @Test("Requests waiting on a rejected refresh all fail as .unauthorized, with one invalidation")
    func concurrentRefreshRejected() async throws {
        let backend = StubBackend()
        let invalidated = Recorder()
        backend.handle { request in
            if request.url?.path() == "/v1/auth/refresh" {
                try await Task.sleep(for: .milliseconds(80))   // keep it in flight while the others pile up
                return (401, [:], .json(APIProblem(.invalidGrant, "Refresh token revoked.")))
            }
            return (401, [:], Data())
        }
        let client = backend.client(store: InMemorySessionStore(.test())) { invalidated.increment("called") }

        let errors = await withTaskGroup(of: APIError?.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    do {
                        _ = try await client.send(Endpoint<Item>(.get, "/v1/me"))
                        return nil
                    } catch {
                        return APIError(error)
                    }
                }
            }
            return await group.reduce(into: [APIError?]()) { $0.append($1) }
        }

        #expect(errors.count == 6)
        #expect(errors.allSatisfy { $0 == .unauthorized })
        #expect(invalidated.count("called") == 1)
    }

    @Test("Tokens about to expire are refreshed before the request")
    func proactiveRefresh() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { request in
            if request.url?.path() == "/v1/auth/refresh" {
                recorder.increment("refresh")
                return (200, [:], .json(Self.tokens("fresh", "r2")))
            }
            recorder.append(request.value(forHTTPHeaderField: "Authorization") ?? "-", to: "auth")
            return (200, [:], .json(Item(value: "ok")))
        }
        let client = backend.client(store: InMemorySessionStore(.test(expiresIn: 10)))
        _ = try await client.send(Endpoint<Item>(.get, "/v1/me"))
        #expect(recorder.count("refresh") == 1)
        #expect(recorder.list("auth") == ["Bearer fresh"])
    }

    @Test("No session → .unauthorized without touching the network")
    func noSession() async {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { _ in recorder.increment("calls"); return (200, [:], Data()) }
        let client = backend.client(store: InMemorySessionStore())
        await #expect(throws: APIError.unauthorized) { _ = try await client.send(Endpoint<Item>(.get, "/v1/me")) }
        #expect(recorder.count("calls") == 0)
    }

    @Test("GET is retried on 503 and succeeds")
    func retriesReplayableRequests() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { _ in
            recorder.increment("calls")
            return recorder.count("calls") < 3 ? (503, [:], Data()) : (200, [:], .json(Item(value: "ok")))
        }
        let client = backend.client(store: InMemorySessionStore(.test()))
        let item = try await client.send(Endpoint<Item>(.get, "/v1/cards"))
        #expect(item.value == "ok")
        #expect(recorder.count("calls") == 3)
    }

    @Test("POST without an idempotency key is never retried")
    func postWithoutKeyIsNotRetried() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { _ in recorder.increment("calls"); return (503, [:], Data()) }
        let client = backend.client(store: InMemorySessionStore(.test()))
        await #expect(throws: APIError.server(status: 503, problem: nil)) {
            _ = try await client.send(try Endpoint<Item>(.post, "/v1/thing", body: Item(value: "x")))
        }
        #expect(recorder.count("calls") == 1)
    }

    @Test("POST with an idempotency key is retried with the same key")
    func idempotentPostRetriedWithSameKey() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { request in
            recorder.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "-", to: "keys")
            return recorder.list("keys").count == 1 ? (502, [:], Data()) : (201, [:], .json(Item(value: "created")))
        }
        let client = backend.client(store: InMemorySessionStore(.test()))
        let item = try await client.send(try Endpoint<Item>(.post, "/v1/connect/requests", body: Item(value: "x"),
                                                            idempotencyKey: "key-123"))
        #expect(item.value == "created")
        #expect(recorder.list("keys") == ["key-123", "key-123"])
    }

    @Test("4xx problems are decoded and not retried")
    func clientErrorsSurfaceProblems() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { _ in
            recorder.increment("calls")
            return (403, [:], .json(APIProblem(.planLimitReached, "The Free plan includes 2 cards.", details: ["limit": "2"])))
        }
        let client = backend.client(store: InMemorySessionStore(.test()))
        do {
            _ = try await client.send(Endpoint<Item>(.get, "/v1/cards"))
            Issue.record("Expected an error")
        } catch let error as APIError {
            #expect(error.code == .planLimitReached)
            #expect(error.statusCode == 403)
            #expect(error.problem?.details?["limit"] == "2")
        }
        #expect(recorder.count("calls") == 1)
    }

    @Test("429 maps to .rateLimited with Retry-After")
    func rateLimited() async throws {
        let backend = StubBackend()
        backend.handle { _ in (429, ["Retry-After": "120"], Data()) }
        let client = backend.client(store: InMemorySessionStore(.test()))
        await #expect(throws: APIError.rateLimited(retryAfter: 120)) {
            _ = try await client.send(Endpoint<Item>(.get, "/v1/cards"))
        }
    }

    @Test("Requests carry JSON, auth and client headers; presigned uploads carry none")
    func headers() async throws {
        let backend = StubBackend()
        let recorder = Recorder()
        backend.handle { request in
            for field in ["Authorization", "Content-Type", "Accept", "X-Tanishly-Client"] {
                recorder.append("\(field)=\(request.value(forHTTPHeaderField: field) ?? "nil")", to: request.url?.path() ?? "")
            }
            return (200, [:], .json(Item(value: "ok")))
        }
        let api = LiveMetlyAPI(client: backend.client(store: InMemorySessionStore(.test(access: "tok"))), urlSession: backend.session())
        _ = try await api.client.send(try Endpoint<Item>(.put, "/v1/cards/x", body: Item(value: "x")))
        #expect(recorder.list("/v1/cards/x") == ["Authorization=Bearer tok", "Content-Type=application/json",
                                                 "Accept=application/json", "X-Tanishly-Client=ios/test"])

        let ticket = UploadTicket(uploadID: "up_1", uploadURL: URL(string: "https://\(backend.host)/upload/up_1")!,
                                  headers: ["Content-Type": "image/jpeg"], expiresAt: .now.addingTimeInterval(60))
        try await api.upload(Data([0xFF, 0xD8, 0xFF]), using: ticket)
        #expect(recorder.list("/upload/up_1") == ["Authorization=nil", "Content-Type=image/jpeg", "Accept=nil", "X-Tanishly-Client=nil"])
    }

    @Test("Log In with Telegram starts at the backend's authorize endpoint with PKCE parameters")
    func telegramAuthorizationURL() throws {
        let backend = StubBackend()
        let api = LiveMetlyAPI(client: backend.client(store: InMemorySessionStore(.test())), urlSession: backend.session())
        let url = try #require(api.telegramAuthorizationURL(codeChallenge: "CH_-1", state: "ST", nonce: "NO"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == backend.host)
        #expect(components.path == "/v1/auth/telegram/authorize")
        #expect(components.queryItems == [URLQueryItem(name: "code_challenge", value: "CH_-1"),
                                          URLQueryItem(name: "state", value: "ST"),
                                          URLQueryItem(name: "nonce", value: "NO")])
    }

    @Test("Offline fails fast as .offline")
    func offline() async {
        let backend = StubBackend()
        backend.handle { _ in throw URLError(.notConnectedToInternet) }
        let client = backend.client(store: InMemorySessionStore(.test()))
        await #expect(throws: APIError.offline) { _ = try await client.send(Endpoint<Item>(.get, "/v1/sync")) }
    }
}
