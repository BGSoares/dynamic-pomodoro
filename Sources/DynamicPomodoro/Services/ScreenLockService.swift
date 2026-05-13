import Foundation

/// Locks the screen by calling the private `SACLockScreenImmediate` symbol
/// in `login.framework` — the same call the Apple-menu "Lock Screen" item
/// and the Ctrl-⌘-Q shortcut ultimately invoke. Takes the user straight to
/// the login window without sleeping the display, so the user's session
/// stays put and the unlock flow is the normal password / Touch ID prompt.
///
/// No entitlements required; same private-framework pattern as
/// `MediaControlService`.
enum ScreenLockService {
    static func lockScreen() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/login.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "SACLockScreenImmediate" as CFString)
        else { return }

        typealias LockScreen = @convention(c) () -> Void
        let lock = unsafeBitCast(pointer, to: LockScreen.self)
        lock()
    }
}
