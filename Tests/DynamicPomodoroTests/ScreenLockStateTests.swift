import Foundation
import Testing
@testable import DynamicPomodoro

/// F2 (SPEC_LOOP_CONTINUITY.md §3.2) is `ScreenLockState == .unlocked` — this
/// pins the contract that `.unknown` (the launch value) is never mistaken
/// for evidence of presence.
@Suite("ScreenLockState")
struct ScreenLockStateTests {
    @Test func unknownDoesNotSatisfyF2() {
        #expect(ScreenLockState.unknown != .unlocked)
    }

    @Test func lockedDoesNotSatisfyF2() {
        #expect(ScreenLockState.locked != .unlocked)
    }

    @Test func unlockedSatisfiesF2() {
        #expect(ScreenLockState.unlocked == .unlocked)
    }
}
