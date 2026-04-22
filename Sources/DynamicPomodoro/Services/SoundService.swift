import AppKit

/// Plays macOS system sounds for timer events.
/// NSSound works without an app bundle, so this always fires when sound is enabled.
enum SoundService {
    /// Satisfying chime — focus session complete.
    static func focusComplete(enabled: Bool) {
        play("Glass", enabled: enabled)
    }

    /// Soft ping — break over, ready to focus again.
    static func breakComplete(enabled: Bool) {
        play("Ping", enabled: enabled)
    }

    /// Gentle pop — break card appeared.
    static func breakReady(enabled: Bool) {
        play("Pop", enabled: enabled)
    }

    private static func play(_ name: String, enabled: Bool) {
        guard enabled else { return }
        // NSSound(named:) loads from /System/Library/Sounds/
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        }
    }
}
