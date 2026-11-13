// SyncEngine — timers that start a later pass: retry with exponential backoff after a failure, and
// the pass that pushes held-back tombstones once their Undo window has passed.
import Foundation

extension SyncEngine {
    func scheduleRetry() {
        failureCount += 1
        let seconds = min(300, 2 * pow(2, Double(failureCount - 1))) * Double.random(in: 0.8...1.2)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.syncNow()
        }
    }

    /// Held-back tombstones go out by themselves once their Undo window has passed. `due` comes from
    /// what the pass's push actually held back (one that fell due mid-pass still gets its pass).
    func scheduleHeldTombstones(due: Date?) {
        heldTombstonesTask?.cancel()
        heldTombstonesTask = nil
        guard let due else { return }
        let delay = max(0, due.timeIntervalSinceNow) + 0.05
        heldTombstonesTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.syncNow()
        }
    }
}
