import Foundation

/// Sends an explicit pause command via the private MediaRemote framework
/// — the same channel macOS's Now Playing widget uses, so it covers
/// Spotify, Music, Podcasts, browser video (YouTube, etc.) without
/// per-app integration. Unlike the hardware Play/Pause key, this is a
/// one-way pause: if nothing is currently playing, the call is a no-op
/// and will not start playback.
enum MediaControlService {
    static func pauseAllMedia() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return }

        typealias SendCommand = @convention(c) (Int, AnyObject?) -> Bool
        let sendCommand = unsafeBitCast(pointer, to: SendCommand.self)
        _ = sendCommand(/* kMRPause */ 1, nil)
    }
}
