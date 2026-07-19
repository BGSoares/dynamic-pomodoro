import Foundation

/// The dynamic Question 2, loaded from `Resources/feedback_question.json`.
/// The routine review agent owns that file — see Resources/AGENT_README.md.
struct FeedbackQuestion: Codable, Equatable {
    enum Kind: String, Codable {
        case multipleChoice = "multiple_choice"
        case openEnded = "open_ended"
    }

    let questionText: String
    let type: Kind
    let options: [String]?
    let revision: Int?

    enum CodingKeys: String, CodingKey {
        case questionText = "question_text"
        case type
        case options
        case revision = "_revision"
    }
}

extension FeedbackQuestion {
    static let fallback = FeedbackQuestion(
        questionText: "What's one thing about Dynamic Pomodoro you'd improve?",
        type: .openEnded,
        options: nil,
        revision: nil
    )
}

enum FeedbackQuestionLoader {
    /// Reads the bundled JSON. Returns nil if missing or malformed —
    /// callers fall back to a generic open-ended prompt rather than crash.
    static func load() -> FeedbackQuestion? {
        let url = BundleResource.url(forResource: "feedback_question", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeedbackQuestion.self, from: data)
    }
}

/// One submitted response. Persisted as a JSON array in Application Support.
struct FeedbackResponse: Codable, Equatable {
    let submittedAt: Date
    /// 1 (😖) … 5 (😍)
    let satisfaction: Int
    /// The Q2 prompt as the user saw it — frozen at submit time so a later
    /// edit to feedback_question.json doesn't desync historical answers.
    let agentQuestionText: String
    let agentQuestionRevision: Int?
    /// For multiple_choice: the selected option. For open_ended: the typed text.
    let agentAnswer: String
    /// Q3 "anything else" — nil when the user left it blank.
    let openEndedAnswer: String?
}

/// Persists feedback responses. Delegates storage to JSONArrayStore.
final class FeedbackStore {
    static let shared = FeedbackStore()
    private let store: JSONArrayStore<FeedbackResponse>

    private convenience init() { self.init(directory: AppSupport.directory) }

    init(directory: URL) {
        store = JSONArrayStore(directory: directory, filename: "feedback.json")
    }

    func append(_ response: FeedbackResponse) { store.append(response) }
}

/// Once-per-user gate. The user is prompted exactly once — submit, skip, or
/// dismiss the sheet, and the flag stays set forever (per macOS account).
enum FeedbackGate {
    private static let promptedKey = "feedbackPromptedAt"

    /// Five sessions: enough exposure for an opinion while first impressions are still fresh.
    static let completedSessionsThreshold = 5

    static var hasBeenPrompted: Bool {
        UserDefaults.standard.object(forKey: promptedKey) != nil
    }

    static func markPrompted(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: promptedKey)
    }

    static func shouldShow(completedFocusCount: Int) -> Bool {
        !hasBeenPrompted && completedFocusCount >= completedSessionsThreshold
    }
}
