import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// Like NotificationService, the SPM-executable launch path (no bundle) is a
/// dead-end here — Sparkle reads SUFeedURL / SUPublicEDKey from Info.plist
/// and only makes sense when running from a real .app bundle. Skip init in
/// that case so `swift run` doesn't try to fetch the appcast or log noise.
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    let controller: SPUStandardUpdaterController?

    private init() {
        guard Bundle.main.bundleIdentifier != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Menu target. When wired via `target = UpdaterService.shared.controller`,
    /// Sparkle's own `checkForUpdates(_:)` selector handles enablement and
    /// disables the item while a check is in progress. This forwarder exists
    /// only for the no-bundle path so the menu item still has a valid action.
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
