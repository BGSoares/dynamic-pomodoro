import Foundation
import Testing
@testable import DynamicPomodoro

/// Nudge placement is a pure fold over a day's break start times — no clock,
/// no persistence, so every rule here is exercised with synthetic dates.
@Suite("Nudges")
struct NudgesTests {
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private let muesli = Nudge(
        id: "muesli", ask: "Three spoons of muesli.",
        because: "Get home not hungry.", afterMinutes: 16 * 60 + 20
    )
    private let bottle = Nudge(
        id: "bottle", ask: "Fill the bottle.",
        because: "Thirst reads as fatigue.", afterMinutes: 11 * 60
    )

    /// A break one minute early is still a break before the time — no nudge.
    @Test func silentBeforeTheNudgeIsDue() {
        #expect(Nudges.forBreak(startingAt: at(16, 19), shownBreakStartsToday: [], from: [muesli]) == nil)
    }

    @Test func ridesTheEarliestBreakAtOrAfterItsTime() {
        #expect(
            Nudges.forBreak(
                startingAt: at(16, 20),
                shownBreakStartsToday: [at(14, 10), at(15, 40)],
                from: [muesli]
            ) == muesli
        )
    }

    /// Once said, it stays said — the later breaks of the day go back to the
    /// ordinary reminder line.
    @Test func firesOnlyOnceADay() {
        let first = at(16, 30)
        #expect(Nudges.forBreak(startingAt: first, shownBreakStartsToday: [], from: [muesli]) == muesli)
        #expect(Nudges.forBreak(startingAt: at(17, 10), shownBreakStartsToday: [first], from: [muesli]) == nil)
    }

    /// Two nudges due at the same break: the fresher one goes first, the older
    /// falls through to the next break rather than being dropped.
    @Test func competingNudgesSpreadAcrossConsecutiveBreaks() {
        let assigned = Nudges.assign(to: [at(16, 30), at(17, 0)], from: [bottle, muesli])
        #expect(assigned.count == 2)
        #expect(assigned[0] == muesli)
        #expect(assigned[1] == bottle)
    }

    /// Declaration order breaks a tie, so assignment never depends on an
    /// unstable sort.
    @Test func nudgesDueAtTheSameTimeKeepDeclarationOrder() {
        let a = Nudge(id: "a", ask: "A", because: "…", afterMinutes: 16 * 60)
        let b = Nudge(id: "b", ask: "B", because: "…", afterMinutes: 16 * 60)
        let assigned = Nudges.assign(to: [at(16, 5), at(16, 30)], from: [a, b])
        #expect(assigned[0] == a)
        #expect(assigned[1] == b)
    }

    /// A day whose breaks all land before the time simply doesn't get it. The
    /// nudge is worth one line on a card, not a fallback delivery channel.
    @Test func aNudgeWhoseBreakNeverCameIsNotDelivered() {
        let assigned = Nudges.assign(to: [at(9, 30), at(11, 30), at(15, 0)], from: [muesli])
        #expect(assigned.allSatisfy { $0 == nil })
    }

    @Test func emptyPoolYieldsNothing() {
        #expect(Nudges.forBreak(startingAt: at(17, 0), shownBreakStartsToday: [], from: []) == nil)
    }

    /// Guards the shipped library, which is hand-edited in source.
    @Test func shippedLibraryIsWellFormed() {
        #expect(Set(Nudges.all.map(\.id)).count == Nudges.all.count)
        #expect(Nudges.all.allSatisfy { (0..<(24 * 60)).contains($0.afterMinutes) })
        #expect(Nudges.all.allSatisfy { !$0.ask.isEmpty && !$0.because.isEmpty })
    }
}
