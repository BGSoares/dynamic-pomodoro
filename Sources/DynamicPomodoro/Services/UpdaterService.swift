import Foundation
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// Like NotificationService, the SPM-executable launch path (no bundle) is a
/// dead-end here — Sparkle reads SUFeedURL / SUPublicEDKey from Info.plist
/// and only makes sense when running from a real .app bundle. Skip init in
/// that case so `swift run` doesn't try to fetch the appcast or log noise.
///
/// Private-repo auth: because the GitHub repo this updates from is private,
/// anonymous HTTP GETs to `releases/latest/download/...` come back 404.
/// We inject a fine-grained PAT (read-only, scoped to this repo's Contents
/// only) as a Bearer token via Sparkle's `httpHeaders` property — applied
/// to the appcast fetch and the zip download alike. The PAT is baked into
/// `Info.plist` at build time from $GITHUB_PAT; it isn't in source, so
/// GitHub's secret-scanning won't auto-revoke it.
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    let controller: SPUStandardUpdaterController?

    private init() {
        guard Bundle.main.bundleIdentifier != nil else {
            controller = nil
            return
        }
        // Defer auto-start so we can set httpHeaders BEFORE the first
        // appcast fetch — otherwise that initial check fires anonymously
        // and 404s against the private repo.
        let c = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        if let pat = Bundle.main.infoDictionary?["GHPrivateRepoPAT"] as? String,
           !pat.isEmpty {
            // `Accept: application/octet-stream` is required so the GitHub
            // releases/assets API returns the binary (rather than JSON
            // metadata) when Sparkle downloads the zip. `raw.githubuser
            // content.com` (where the appcast lives) ignores Accept and
            // serves the file regardless, so the same header is safe for
            // the appcast fetch.
            c.updater.httpHeaders = [
                "Authorization": "Bearer \(pat)",
                "Accept": "application/octet-stream",
            ]
        }
        c.startUpdater()
        controller = c
    }

    /// Menu target. When wired via `target = UpdaterService.shared.controller`,
    /// Sparkle's own `checkForUpdates(_:)` selector handles enablement and
    /// disables the item while a check is in progress. This forwarder exists
    /// only for the no-bundle path so the menu item still has a valid action.
    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
