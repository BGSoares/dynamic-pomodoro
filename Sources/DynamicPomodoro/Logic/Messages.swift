import Foundation

/// Reminder messages — §4.5.
/// Shown on first break of day, and on the break card following a skipped break.
enum ReminderMessages {
    static let pool: [String] = [
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
        "Breaks aren't a tax on productivity. They're the mechanism by which it compounds."
    ]

    static func random(excluding last: String? = nil, rng: inout SystemRandomNumberGenerator) -> String {
        let candidates = pool.filter { $0 != last }
        return (candidates.isEmpty ? pool : candidates).randomElement(using: &rng) ?? pool[0]
    }
}
