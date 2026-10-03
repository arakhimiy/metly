import Foundation

/// `wss://{host}/v1/realtime` — authenticated with `Authorization: Bearer …` on the upgrade request.
///
/// Fans one socket out to any number of `AsyncStream`s, reconnects with exponential backoff while
/// someone is listening, answers app-level `ping`s and emits `.syncAvailable` after every
/// (re)connect so consumers catch up on anything missed while disconnected.
actor LiveRealtimeConnection: RealtimeAPI {
    private let client: APIClient
    private let urlSession: URLSession
    private var subscribers: [UUID: AsyncStream<ConnectEvent>.Continuation] = [:]
    private var runTask: Task<Void, Never>?
    private var runID = UUID()
    private var state: RealtimeState = .disconnected

    init(client: APIClient, urlSession: URLSession) {
        self.client = client
        self.urlSession = urlSession
    }

    var realtimeURL: URL {
        var components = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = client.baseURL.scheme == "http" ? "ws" : "wss"
        let url = components?.url ?? client.baseURL
        return url.appending(path: "/v1/realtime")
    }

    func connectEvents() -> AsyncStream<ConnectEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectEvent.self, bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        continuation.yield(.stateChanged(state))
        if runTask == nil {
            let id = UUID()
            runID = id
            runTask = Task { await self.run(id) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty {
            runTask?.cancel()
            runTask = nil
        }
    }

    private func broadcast(_ event: ConnectEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func setState(_ newState: RealtimeState) {
        guard newState != state else { return }
        state = newState
        broadcast(.stateChanged(newState))
    }

    private func run(_ id: UUID) async {
        var failures = 0
        while !Task.isCancelled, !subscribers.isEmpty {
            setState(.connecting)
            do {
                let token = try await client.validAccessToken()
                var request = URLRequest(url: realtimeURL)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let socket = urlSession.webSocketTask(with: request)
                socket.resume()
                try await withTaskCancellationHandler {
                    try await ping(socket)
                    setState(.connected)
                    failures = 0
                    broadcast(.syncAvailable)
                    try await receive(from: socket)
                } onCancel: {
                    socket.cancel(with: .goingAway, reason: nil)
                }
            } catch APIError.unauthorized {
                // No session — stay down until a new stream is requested after sign-in.
                setState(.disconnected)
                break
            } catch {
                failures += 1
            }
            setState(.disconnected)
            guard !Task.isCancelled else { break }
            let delay = Duration.seconds(min(60, 1 << min(failures, 6)))
            try? await Task.sleep(for: delay * Double.random(in: 0.8...1.2))
        }
        if runID == id { runTask = nil }
        setState(.disconnected)
    }

    private func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func receive(from socket: URLSessionWebSocketTask) async throws {
        let decoder = MetlyJSON.makeDecoder()
        while !Task.isCancelled {
            let data: Data
            switch try await socket.receive() {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            guard let message = try? decoder.decode(RealtimeMessage.self, from: data) else { continue }
            if message.type == RealtimeMessage.Kind.ping.rawValue {
                try await socket.send(.string(#"{"type":"pong"}"#))
            } else if let event = message.event {
                broadcast(event)
            }
        }
    }
}
