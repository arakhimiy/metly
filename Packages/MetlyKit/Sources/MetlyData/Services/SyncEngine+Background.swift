// SyncEngine — the BGAppRefreshTask: registering, scheduling and running a background pass.
import BackgroundTasks
import Foundation

extension SyncEngine {
    // MARK: Background task (BGAppRefreshTask `app.nameshake.ios.sync`)

    /// Call once from the app target before launch finishes (e.g. `MetlyApp.init`).
    public func registerBackgroundTasks() {
        guard !Self.backgroundTasksRegistered else { return }
        Self.backgroundTasksRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier,
                                                                         using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.runBackgroundTask(task)
            }
        }
    }

    /// Asks iOS for a background sync in ~15 min. Called after every successful pass; the app
    /// may also call it when entering the background.
    public func scheduleBackgroundSync(after interval: TimeInterval = 15 * 60) {
        guard Self.backgroundTasksRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func runBackgroundTask(_ task: BGTask) {
        scheduleBackgroundSync()
        let work = backgroundPass()
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            task.setTaskCompleted(success: await work.value)
        }
    }

    /// The work behind the BGTask. Cancelling it (expiration) cancels the pass itself — awaiting a
    /// pass doesn't react to cancellation — so `setTaskCompleted` is called before iOS kills the app.
    func backgroundPass() -> Task<Bool, Never> {
        Task { [weak self] () -> Bool in
            guard let self else { return false }
            let pass = self.startPass()
            await withTaskCancellationHandler {
                await pass.value
            } onCancel: {
                pass.cancel()
            }
            return !Task.isCancelled && self.status == .idle
        }
    }
}
