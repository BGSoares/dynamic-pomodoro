import Testing
@testable import DynamicPomodoro

@Suite("BreakLogic")
struct BreakLogicTests {
    @Test func floorAppliesForShortFocus() {
        #expect(BreakLogic.breakDuration(forFocusMinutes: 20) == 5)
        #expect(BreakLogic.breakDuration(forFocusMinutes: 25) == 5)
    }

    @Test func twentyPercentAppliesAboveFloor() {
        #expect(BreakLogic.breakDuration(forFocusMinutes: 30) == 6)
        #expect(BreakLogic.breakDuration(forFocusMinutes: 40) == 8)
    }

    @Test func durationBandSplits() {
        #expect(BreakLogic.durationBand(forBreakMinutes: 5) == .short)
        #expect(BreakLogic.durationBand(forBreakMinutes: 6) == .short)
        #expect(BreakLogic.durationBand(forBreakMinutes: 7) == .medium)
        #expect(BreakLogic.durationBand(forBreakMinutes: 8) == .medium)
    }
}
