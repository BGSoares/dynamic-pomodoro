import Foundation
import Testing
@testable import DynamicPomodoro

/// Settings are read from UserDefaults, which is not trusted input – and the
/// one shared focus minimum became two on 2026-10-05, so a stored value from
/// before then has to land on both.
@Suite("Settings")
final class SettingsTests {
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "SettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func freshDefaultsStartWithEqualMinimums() {
        let s = Settings(defaults: defaults)
        #expect(s.minFocusStartMinutes == 20)
        #expect(s.minFocusEndMinutes == 20)
        #expect(s.maxFocusMinutes == 40)
    }

    /// The pre-split minimum seeds both floors, so an upgrade keeps the
    /// curve exactly where the user had it.
    @Test func legacyMinimumSeedsBothFloors() {
        defaults.set(25, forKey: "minFocusMinutes")
        let s = Settings(defaults: defaults)
        #expect(s.minFocusStartMinutes == 25)
        #expect(s.minFocusEndMinutes == 25)
    }

    @Test func storedFloorsWinOverTheLegacyMinimum() {
        defaults.set(25, forKey: "minFocusMinutes")
        defaults.set(15, forKey: "minFocusStartMinutes")
        defaults.set(30, forKey: "minFocusEndMinutes")
        let s = Settings(defaults: defaults)
        #expect(s.minFocusStartMinutes == 15)
        #expect(s.minFocusEndMinutes == 30)
    }

    @Test func changesPersistUnderTheirOwnKeys() {
        let s = Settings(defaults: defaults)
        s.minFocusStartMinutes = 15
        s.minFocusEndMinutes = 35
        let reloaded = Settings(defaults: defaults)
        #expect(reloaded.minFocusStartMinutes == 15)
        #expect(reloaded.minFocusEndMinutes == 35)
        #expect(defaults.object(forKey: "minFocusMinutes") == nil, "the legacy key is never written")
    }

    @Test func pauseMediaOnBreakIsOffUntilTickedAndPersists() {
        let s = Settings(defaults: defaults)
        #expect(!s.pauseMediaOnBreak)
        s.pauseMediaOnBreak = true
        #expect(Settings(defaults: defaults).pauseMediaOnBreak)
    }

    /// The maximum is held above both floors, whichever is higher – the
    /// same rule the steppers enforce, applied to whatever the file says.
    @Test func maximumIsClampedAboveTheHigherFloor() {
        defaults.set(20, forKey: "minFocusStartMinutes")
        defaults.set(45, forKey: "minFocusEndMinutes")
        defaults.set(30, forKey: "maxFocusMinutes")
        let s = Settings(defaults: defaults)
        #expect(s.maxFocusMinutes == 50)
        #expect(s.minFocusStartMinutes == 20)
        #expect(s.minFocusEndMinutes == 45)
    }

    @Test func outOfRangeFloorsAreClampedIntoTheSteppersRange() {
        defaults.set(-5, forKey: "minFocusStartMinutes")
        defaults.set(500, forKey: "minFocusEndMinutes")
        let s = Settings(defaults: defaults)
        #expect(s.minFocusStartMinutes == 5)
        #expect(s.minFocusEndMinutes == 60)
        #expect(s.maxFocusMinutes == 65)
    }
}
