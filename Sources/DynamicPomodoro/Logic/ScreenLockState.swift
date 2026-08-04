import Foundation

/// Whether the screen is known locked, known unlocked, or not yet observed
/// (SPEC_LOOP_CONTINUITY.md §3.1). `.unknown` is the launch value and is
/// **never** treated as unlocked — the break-end foreground (§3.2, F2) and
/// the unlock countdown both require a positively observed unlock, not an
/// assumption. Pure value type; tracked as state by `ScreenLockMonitor`.
enum ScreenLockState: Equatable {
    case unknown
    case locked
    case unlocked
}
