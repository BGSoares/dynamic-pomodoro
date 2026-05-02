import AppKit
import IOKit.hidsystem

/// Sends the system Play/Pause media key so any actively playing
/// audio/video (YouTube, Spotify, Music, …) pauses. The signal matches
/// what the hardware Play/Pause key emits, and macOS routes it to the
/// most-recently-active media app — so no per-app integration is needed.
enum MediaControlService {
    static func pauseAllMedia() {
        sendMediaKey(NX_KEYTYPE_PLAY)
    }

    private static func sendMediaKey(_ key: Int32) {
        // System-defined media-key events encode press/release as NX_KEYDOWN /
        // NX_KEYUP packed into both the modifier-flag word (shifted left by 8)
        // and the data1 second byte. The values aren't exposed as Swift
        // constants so we name them locally to keep the bit layout legible.
        let nxKeyDown = 0xa
        let nxKeyUp = 0xb
        for nxKeyState in [nxKeyDown, nxKeyUp] {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(nxKeyState) << 8)
            let data1 = (Int(key) << 16) | (nxKeyState << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                data1: data1,
                data2: -1
            ) else { return }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
