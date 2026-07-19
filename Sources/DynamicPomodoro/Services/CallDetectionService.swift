import CoreAudio

/// Detects whether the user is on a call, app-agnostically: every meeting
/// app (Meet in a browser, Zoom, Teams, FaceTime, Slack huddles) keeps the
/// microphone input stream open for the whole call — even while muted — so
/// "some input-capable audio device is running" is a reliable live-call
/// signal without naming any vendor.
///
/// Reads HAL device *state* only: no capture, no TCC prompt, a handful of
/// property queries (polled at 1Hz while a session runs).
///
/// Known trade-off: duplex devices (e.g. AirPods) report "running somewhere"
/// device-wide, so music playback on such a device can read as a call.
/// Sensitivity is deliberate — a false positive defers a break (bounded by
/// the reducer's 30-minute cap, visible in the pending UI, overridable with
/// one click), while a false negative throws the overlay and screen lock
/// into a live meeting.
enum CallDetectionService {
    static func isOnCall() -> Bool {
        inputDeviceIDs().contains(where: isRunningSomewhere)
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasInputStreams)
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running) == noErr && running != 0
    }
}
