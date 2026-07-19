import Foundation
import UserNotifications
import AppKit

/// Thin wrapper around UserNotifications.
///
/// UNUserNotificationCenter.current() crashes when the process has no app bundle
/// (i.e. running via `swift run`). Guard against this by checking for a bundle
/// identifier before touching the center — notifications are silently skipped when
/// there's no bundle, which is fine for the SPM-executable launch path.
final class NotificationService {
    static let shared = NotificationService()

    private var center: UNUserNotificationCenter?

    private init() {
        if Bundle.main.bundleIdentifier != nil {
            center = UNUserNotificationCenter.current()
        }
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    func notify(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        // No cached authorization flag: the system drops the request itself
        // when unauthorized, and the flag was written from UN callback
        // threads — a data race for zero benefit.
        center.add(req)
    }
}
