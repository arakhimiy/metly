import Foundation

/// Runs `work` in passes that never interleave. Calls made while a pass is running are folded into
/// one more pass, and every call returns only once a pass that started after it has finished.
///
/// The second guarantee matters for "Snooze 1 Day": the notification delegate awaits `reschedule()`
/// before returning, and iOS may suspend the app right after. Returning while an older pass — one that
/// read the store before the snooze — is still in flight would leave the snoozed reminder without a
/// pending notification.
@MainActor
final class SerialPassRunner {
    private let work: @MainActor () async -> Void
    private var needsAnotherPass = false
    private var running: Task<Void, Never>?

    init(work: @escaping @MainActor () async -> Void) {
        self.work = work
    }

    func run() async {
        needsAnotherPass = true
        if let running {
            // The running loop checks `needsAnotherPass` after its current pass, so it covers this call.
            await running.value
            return
        }
        let task = Task { [weak self] in
            while let self, self.needsAnotherPass {
                self.needsAnotherPass = false
                await self.work()
            }
            // Same job as the final `needsAnotherPass` check: no call can slip in between.
            self?.running = nil
        }
        running = task
        await task.value
    }
}
