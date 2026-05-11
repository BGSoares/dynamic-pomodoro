import Foundation
import EventKit

/// Mirrors a break session to the user's Calendar so it syncs via iCloud to
/// iPhone / Apple Watch. The use case: glancing at break time-remaining
/// while away from the Mac (e.g. on a walk) via the Calendar lock-screen
/// widget or a Watch complication.
///
/// Events are created at break start and removed when the break ends —
/// whether it completed normally or was skipped. If the app crashes mid-break
/// the event remains but will auto-expire at its end time, so the worst case
/// is a cosmetic leftover in the user's calendar.
///
/// Mirrors `NotificationService`: gracefully no-ops when the process has no
/// bundle ID (running via `swift run`), because without a bundled Info.plist
/// the OS has no usage description and would reject the permission prompt.
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    struct CalendarInfo: Identifiable, Hashable {
        let id: String
        let title: String
        let sourceTitle: String
    }

    private let hasBundleID: Bool
    private let store: EKEventStore?

    @Published private(set) var authorized: Bool = false
    @Published private(set) var authorizationDenied: Bool = false

    private init() {
        hasBundleID = Bundle.main.bundleIdentifier != nil
        store = hasBundleID ? EKEventStore() : nil
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let ok: Bool
        if #available(macOS 14.0, *) {
            ok = (status == .fullAccess)
        } else {
            ok = (status == .authorized)
        }
        setStateOnMain(authorized: ok && hasBundleID,
                       denied: (status == .denied || status == .restricted))
    }

    /// Request access (full access — we need to read back events to delete
    /// them cleanly when a break ends). Completion runs on the main queue.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        guard let store else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refreshAuthorizationStatus()
                completion(granted)
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    // MARK: - Calendars

    /// Calendars the user may write to, preferring those that sync (iCloud etc.)
    /// over local-only calendars — a local-only calendar wouldn't show on the phone.
    var writableCalendars: [CalendarInfo] {
        guard authorized, let store else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { lhs, rhs in
                let lPri = sourcePriority(lhs.source)
                let rPri = sourcePriority(rhs.source)
                if lPri != rPri { return lPri < rPri }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map { CalendarInfo(id: $0.calendarIdentifier,
                                title: $0.title,
                                sourceTitle: $0.source.title) }
    }

    /// Identifier of a sensible default calendar — the first iCloud one, else
    /// the system default. Used when the user has sync enabled but hasn't
    /// picked a calendar yet.
    var suggestedCalendarIdentifier: String? {
        guard let store else { return nil }
        if let icloud = store.calendars(for: .event)
            .first(where: { $0.allowsContentModifications && $0.source.sourceType == .calDAV }) {
            return icloud.calendarIdentifier
        }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: - Events

    /// Returns the created event's identifier, or nil on failure.
    @discardableResult
    func createBreakEvent(
        start: Date,
        end: Date,
        title: String,
        calendarIdentifier: String?
    ) -> String? {
        guard authorized, let store else { return nil }
        let targetCalendar: EKCalendar? = {
            if let id = calendarIdentifier, let cal = store.calendar(withIdentifier: id) {
                return cal
            }
            return store.defaultCalendarForNewEvents
        }()
        guard let calendar = targetCalendar else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        event.notes = "Auto-created by Dynamic Pomodoro."
        // Suppress default reminders — the break has its own completion sound.
        event.alarms = []

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    func removeEvent(withIdentifier id: String) {
        guard let store, let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Helpers

    private func sourcePriority(_ source: EKSource) -> Int {
        switch source.sourceType {
        case .calDAV: return 0    // iCloud / work CalDAV — syncs to phone
        case .mobileMe: return 0  // legacy iCloud predecessor — treat like CalDAV
        case .exchange: return 1  // syncs too
        case .subscribed: return 2
        case .birthdays: return 3
        case .local: return 4     // local-only — won't show on phone
        @unknown default: return 5
        }
    }

    private func setStateOnMain(authorized: Bool, denied: Bool) {
        if Thread.isMainThread {
            self.authorized = authorized
            self.authorizationDenied = denied
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.authorized = authorized
                self?.authorizationDenied = denied
            }
        }
    }
}
