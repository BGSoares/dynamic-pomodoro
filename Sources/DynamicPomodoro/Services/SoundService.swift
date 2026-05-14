import AppKit

/// Plays macOS system sounds for timer events.
/// NSSound works without an app bundle, so this always fires.
enum SoundService {
    /// Satisfying chime — focus session complete.
    static func focusComplete() { play("Glass") }

    /// Soft ping — break over, ready to focus again.
    static func breakComplete() { play("Ping") }

    private static func play(_ name: String) {
        // NSSound(named:) loads from /System/Library/Sounds/
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        }
    }
}
