import Foundation

/// Reminder messages — §4.5.
/// Shown on first break of day, on the break card following a skipped break,
/// and on every Nth break otherwise (see TimerController).
enum ReminderMessages {
    static let pool: [String] = [
        // Science of rest
        "Rest is when your brain consolidates what you just learned.",
        "Directed attention is a limited resource. Breaks refill it.",
        "Movement between sessions clears metabolic byproducts from the brain.",
        "Your eyes haven't looked at anything further than 60cm for 40 minutes. Fix that.",
        "The default mode network — active when you rest — is where integration happens.",
        "Posture collapses silently during focus. A break is when you catch it.",
        "Brief physical exertion between cognitive tasks improves the next task's quality.",
        "Micro-breaks reduce the build-up of mental fatigue hormones.",
        "Even 5 minutes of non-screen time meaningfully reduces eye strain.",
        "Slow nasal breathing in breaks lowers cortisol for the next focus session.",
        "Standing up resets circulation that a chair has been quietly restricting.",
        "The best ideas arrive when the prefrontal cortex stops gripping the problem.",
        "Sustained attention without rest doesn't produce better work — it produces more errors.",
        "Breaks aren't a tax on productivity. They're the mechanism by which it compounds.",

        // Cost of skipping
        "Skipping a break borrows from your next focus session, with interest.",
        "If you don't take the break, your body will eventually take it for you — louder.",
        "A break taken now prevents the long, foggy hour at 4pm.",
        "Two hours without a break costs you the next two hours of quality.",
        "The cost of a break is 5 minutes. The cost of skipping it is the rest of the day.",

        // Cycling metaphors
        "Pros recover between intervals. So do you.",
        "Even in a breakaway, riders take the wheel of the next rider. Sit on for 5 minutes.",
        "Easy spinning between hard efforts is what makes you strong. Same brain, same rule.",
        "No rider trains through fatigue — they rest through it. Your prefrontal cortex deserves the same respect.",
        "Between climbs, you eat. Between sessions, you rest. Both are non-negotiable.",

        // Commitment
        "The work will still be there in 5 minutes. So will you, only sharper.",
        "Your best ideas are waiting on the other side of stopping. They will not come while you push."
    ]

    static func random(excluding last: String? = nil, rng: inout SystemRandomNumberGenerator) -> String {
        let candidates = pool.filter { $0 != last }
        return (candidates.isEmpty ? pool : candidates).randomElement(using: &rng) ?? pool[0]
    }
}

/// Short, sharper one-liners shown under the hold-to-skip button while the user
/// is mid-hold. Goal: one final beat of resistance before the skip commits.
/// Kept separate from the main pool because they're addressed *to* the user
/// in the moment of skipping — not general reminders.
enum SkipNudgeMessages {
    static let pool: [String] = [
        "The session you protect by skipping will be the worse for it.",
        "Your future self at 4pm is asking you to let go.",
        "Pros recover. Are you sure?",
        "Five minutes now buys you the rest of the afternoon.",
        "Your legs need this too."
    ]

    static func random(rng: inout SystemRandomNumberGenerator) -> String {
        pool.randomElement(using: &rng) ?? pool[0]
    }
}
