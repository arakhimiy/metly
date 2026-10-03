import Foundation
import Network
import Synchronization

/// Triggers (first time) and reads the Local Network permission.
///
/// iOS has no API for this permission, so we advertise a short-lived Bonjour service of our own
/// type (`_metly-connect._tcp`, declared in `NSBonjourServices`) and browse for it:
/// - the browser finds our own service → access granted;
/// - the browser waits with `kDNSServiceErr_PolicyDenied` → access denied;
/// - neither within `timeout` (the user hasn't answered yet) → undetermined.
/// Once the user has decided, probing never prompts again, so it's also used to refresh the status.
nonisolated enum LocalNetworkProbe {
    static let serviceType = "_metly-connect._tcp"
    /// `kDNSServiceErr_PolicyDenied` from dns_sd.h.
    static let policyDeniedError: Int32 = -65570

    @concurrent
    static func requestAccess(timeout: Duration) async -> LocalNetworkAccess {
        let queue = DispatchQueue(label: "com.metly.app.local-network-probe")
        let serviceName = "metly-probe-\(UUID().uuidString.prefix(8))"

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            return .undetermined
        }
        listener.service = NWListener.Service(name: serviceName, type: serviceType)
        listener.newConnectionHandler = { @Sendable connection in connection.cancel() }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        let gate = ResumeGate()
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            gate.resume(.undetermined)
        }

        let access = await withCheckedContinuation { (continuation: CheckedContinuation<LocalNetworkAccess, Never>) in
            gate.install(continuation)
            browser.stateUpdateHandler = { @Sendable state in
                switch state {
                case .waiting(let error), .failed(let error):
                    if case .dns(let code) = error, code == policyDeniedError {
                        gate.resume(.denied)
                    } else if case .failed = state {
                        gate.resume(.undetermined)
                    }
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { @Sendable results, _ in
                let foundSelf = results.contains { result in
                    if case .service(let name, _, _, _) = result.endpoint { name == serviceName } else { false }
                }
                if foundSelf { gate.resume(.granted) }
            }
            listener.stateUpdateHandler = { @Sendable state in
                if case .failed = state { gate.resume(.undetermined) }
            }
            listener.start(queue: queue)
            browser.start(queue: queue)
        }

        timeoutTask.cancel()
        browser.cancel()
        listener.cancel()
        return access
    }
}

/// Resumes a continuation exactly once, from whichever callback fires first
/// (including one that fires before the continuation is installed).
private nonisolated final class ResumeGate: Sendable {
    private struct Storage {
        var continuation: CheckedContinuation<LocalNetworkAccess, Never>?
        var earlyResult: LocalNetworkAccess?
        var isFinished = false
    }

    private let storage = Mutex(Storage())

    func install(_ continuation: CheckedContinuation<LocalNetworkAccess, Never>) {
        let early = storage.withLock { state -> LocalNetworkAccess? in
            if let early = state.earlyResult {
                state.isFinished = true
                return early
            }
            state.continuation = continuation
            return nil
        }
        if let early {
            continuation.resume(returning: early)
        }
    }

    func resume(_ value: LocalNetworkAccess) {
        let waiting = storage.withLock { state -> CheckedContinuation<LocalNetworkAccess, Never>? in
            guard !state.isFinished else { return nil }
            if let continuation = state.continuation {
                state.continuation = nil
                state.isFinished = true
                return continuation
            }
            if state.earlyResult == nil {
                state.earlyResult = value
            }
            return nil
        }
        waiting?.resume(returning: value)
    }
}
