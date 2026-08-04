import AppKit

/// Tracks whether the screen is locked, unlocked, or not yet known
/// (SPEC_LOOP_CONTINUITY.md §3.1) by observing the same distributed
/// notification pair the login window posts on every lock/unlock. Absorbed
/// here from `AutoStartService` (formerly `UnlockAutoStartService`), which
/// used to own these observers itself — change 2's break-end foreground
/// gate (§3.2, F2) needs the signal as *state*, not just as an edge, so the
/// observation now lives in one place with two consumers.
@MainActor
final class ScreenLockMonitor: ObservableObject {
    @Published private(set) var state: ScreenLockState = .unknown

    /// Fired after `state` becomes `.unlocked` — `AutoStartService`'s unlock
    /// countdown trigger.
    var onUnlock: (() -> Void)?
    /// Fired after `state` becomes `.locked` — lets a live countdown dismiss
    /// itself without suppression.
    var onLock: (() -> Void)?

    private var unlockObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?

    init() {
        let center = DistributedNotificationCenter.default()
        unlockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state = .unlocked
                self.onUnlock?()
            }
        }
        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state = .locked
                self.onLock?()
            }
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        if let unlockObserver { center.removeObserver(unlockObserver) }
        if let lockObserver { center.removeObserver(lockObserver) }
    }
}
