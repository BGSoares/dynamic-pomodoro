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

    /// true only when running inside a proper .app bundle
    private let hasBundleID: Bool
    private var center: UNUserNotificationCenter?
    private var authorized = false

    private init() {
        hasBundleID = Bundle.main.bundleIdentifier != nil
        if hasBundleID {
            center = UNUserNotificationCenter.current()
        }
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                    self?.authorized = ok
                }
            } else {
                self?.authorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func notify(title: String, body: String, playSound: Bool) {
        guard authorized, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(req)
    }
}
