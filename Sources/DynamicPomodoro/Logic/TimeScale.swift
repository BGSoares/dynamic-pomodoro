import Foundation

/// How many real seconds one *prescribed* minute lasts. 60, always, in real
/// use — except under the DEBUG-only `DP_SECONDS_PER_MINUTE` override, which
/// compresses every prescribed duration so a whole focus → break → focus
/// loop can be watched end-to-end in under a minute (PURPOSE principle 9):
///
///     DP_SECONDS_PER_MINUTE=2 swift run
///
/// runs a 20-minute session in 40 seconds, its 5-minute break in 10, and the
/// 30-second break screen lock at 1 second in. Compression changes *time and
/// nothing else*: the same reducer, the same selection, the same chimes and
/// lock — which is what makes a compressed run a faithful preview rather than
/// a separate code path. Release builds cannot be compressed: a friction-free
/// fast-forward in daily use would be a break skip that never earns its
/// 15-second hold.
///
/// While compressed, on-disk persistence auto-redirects to a scratch
/// directory (see `AppSupport.directory`) so a test run never writes
/// fabricated sessions into the real log.
enum TimeScale {
    static let secondsPerMinute: Int = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["DP_SECONDS_PER_MINUTE"],
           let value = Int(raw) {
            return min(max(value, 1), 60)
        }
        #endif
        return 60
    }()

    static var isCompressed: Bool { secondsPerMinute != 60 }

    /// Prescribed minutes → real seconds.
    static func seconds(ofMinutes minutes: Int) -> Int {
        minutes * secondsPerMinute
    }

    /// A timing constant authored in real seconds at normal scale → real
    /// seconds at the current scale.
    static func seconds(_ normalSeconds: TimeInterval) -> TimeInterval {
        normalSeconds * TimeInterval(secondsPerMinute) / 60.0
    }
}
