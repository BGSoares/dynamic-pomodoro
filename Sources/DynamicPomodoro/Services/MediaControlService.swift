import Foundation

/// Sends an explicit pause through the private MediaRemote framework – the
/// channel macOS's own Now Playing controls use – so it reaches Spotify,
/// Music, Podcasts and browser video alike with no per-app integration and
/// no permission prompt. Unlike the hardware Play/Pause key it is one-way:
/// with nothing playing it does nothing, and it never starts playback.
enum MediaControlService {
    private typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool
    private static let kMRPause = 1

    /// Resolved once. Nil if the framework or symbol ever disappears, in
    /// which case pausing quietly becomes a no-op rather than a crash.
    private static let sendCommand: SendCommand? = {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: SendCommand.self)
    }()

    static func pauseAllMedia() {
        _ = sendCommand?(kMRPause, nil)
    }
}
