import Foundation

/// Carries the Telegram app's answer back to the sign-in waiting for it.
///
/// In the Telegram-app flow the user approves inside Telegram, which then opens this app through the
/// Universal Link @BotFather generated for it (`https://app<id>-login.tg.dev?code=…`). The app's
/// `onOpenURL` / `onContinueUserActivity` hand that link here, and the waiting `signIn()` resumes.
/// Coming back without the link (the user switched back by hand) cancels the attempt after a short
/// grace period, so the button never stays stuck.
public final class TelegramAppReturn {
    public static let shared = TelegramAppReturn()

    /// How long the app waits, once active again, for the link to arrive before giving up.
    var graceAfterReturn: Duration = .seconds(2)

    private var pending: CheckedContinuation<URL?, any Error>?
    private var leftApp = false
    private var giveUp: Task<Void, Never>?

    init() {}

    /// True for the Universal Link the Telegram app opens after a sign-in.
    public nonisolated static func isTelegramReturn(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host()?.hasSuffix("-login.tg.dev") ?? false)
    }

    /// Hands a link to the waiting sign-in. Returns true when the link was Telegram's (handled or not),
    /// so the caller doesn't route it anywhere else.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard Self.isTelegramReturn(url) else { return false }
        giveUp?.cancel()
        giveUp = nil
        let continuation = pending
        pending = nil
        continuation?.resume(returning: url)
        return true
    }

    /// The app went to the background (to Telegram) while a sign-in waits.
    public func appDidLeave() {
        if pending != nil { leftApp = true }
    }

    /// The app is active again: if no link arrives shortly, the user came back without approving.
    public func appDidBecomeActive() {
        guard pending != nil, leftApp else { return }
        giveUp?.cancel()
        giveUp = Task { [weak self, graceAfterReturn] in
            try? await Task.sleep(for: graceAfterReturn)
            guard !Task.isCancelled else { return }
            self?.cancelPending()
        }
    }

    /// Opens `link` in Telegram and waits for its link back; nil when Telegram could not be opened.
    /// Waiting starts before opening, so leaving for Telegram is always noticed. A newer attempt
    /// cancels an older one.
    func run(opening link: URL, with open: @escaping @MainActor (URL) async -> Bool) async throws -> URL? {
        cancelPending()
        leftApp = false
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                Task { @MainActor [weak self] in
                    guard await open(link) == false, let self, let pending = self.pending else { return }
                    self.pending = nil
                    pending.resume(returning: nil)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPending() }
        }
    }

    private func cancelPending() {
        giveUp?.cancel()
        giveUp = nil
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: TelegramSignInError.cancelled)
    }
}
