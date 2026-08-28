import Foundation

/// SplitMix64 — a tiny deterministic RNG for rehearsals. The same seed
/// replays the same day, byte for byte, which is what makes a transcript
/// diffable and a reported bug reproducible. Not cryptographic; never used
/// outside rehearsal and tests (the app itself keeps
/// `SystemRandomNumberGenerator`).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
