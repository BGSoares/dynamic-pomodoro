import AppKit
import IOKit.hidsystem

/// Sends the system Play/Pause media key so any actively playing
/// audio/video (YouTube, Spotify, Music, …) pauses. The signal matches
/// what the hardware Play/Pause key emits, and macOS routes it to the
/// most-recently-active media app — so no per-app integration is needed.
enum MediaControlService {
    static func pauseAllMedia(enabled: Bool) {
        guard enabled else { return }
        sendMediaKey(NX_KEYTYPE_PLAY)
    }

    private static func sendMediaKey(_ key: Int32) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xa00 : 0xb00)
            let data1 = (Int(key) << 16) | ((isDown ? 0xa : 0xb) << 8)
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
