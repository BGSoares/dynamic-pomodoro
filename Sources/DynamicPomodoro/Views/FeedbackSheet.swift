import SwiftUI

/// One-shot survey: Q1 emoji (fixed), Q2 dynamic (see AGENT_README.md), Q3 open-ended (fixed).
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let resolvedQuestion: FeedbackQuestion
    let onSubmit: (FeedbackResponse) -> Void

    @State private var step: Int = 0
    @State private var satisfaction: Int? = nil
    @State private var q2Choice: String? = nil
    @State private var q2Text: String = ""
    @State private var q3Text: String = ""

    private let totalQuestions = 3
    private let emojis = ["😖", "😕", "😐", "🙂", "😍"]

    private var q2Trimmed: String { q2Text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var q3Trimmed: String { q3Text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var q2Options: [String]? {
        guard resolvedQuestion.type == .multipleChoice,
              let opts = resolvedQuestion.options, !opts.isEmpty else { return nil }
        return opts
    }

    init(question: FeedbackQuestion?, onSubmit: @escaping (FeedbackResponse) -> Void) {
        self.resolvedQuestion = question ?? .fallback
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 36)
            footer
        }
        .frame(width: 500, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            ProgressDots(current: min(step, totalQuestions - 1), total: totalQuestions)
            if step < totalQuestions {
                Button("Skip") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, 22)
        .padding(.horizontal, 22)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch step {
            case 0:
                card1.transition(.cardTransition)
            case 1:
                card2.transition(.cardTransition)
            case 2:
                card3.transition(.cardTransition)
            default:
                thankYou.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: step)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if step < totalQuestions {
            HStack {
                if step > 0 {
                    Button(action: { withAnimation { step -= 1 } }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                primaryButton
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 22)
            .frame(height: 56)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if step == 1, q2Options == nil {
            Button("Next") { withAnimation { step = 2 } }
                .prominentLarge()
                .disabled(q2Trimmed.isEmpty)
        } else if step == 2 {
            Button(q3Trimmed.isEmpty ? "Skip" : "Submit") { submit() }
                .prominentLarge()
        }
    }

    // MARK: - Cards

    private var card1: some View {
        VStack(spacing: 32) {
            QuestionTitle("How does Dynamic Pomodoro feel for you so far?")
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    EmojiButton(
                        emoji: emojis[i],
                        isSelected: satisfaction == i + 1,
                        action: { satisfaction = i + 1; advance(to: 1) }
                    )
                }
            }
        }
        .padding(.top, 28)
    }

    private var card2: some View {
        VStack(spacing: 22) {
            QuestionTitle(resolvedQuestion.questionText)
            if let opts = q2Options {
                VStack(spacing: 8) {
                    ForEach(opts, id: \.self) { opt in
                        OptionButton(label: opt, isSelected: q2Choice == opt, action: { q2Choice = opt; advance(to: 2) })
                    }
                }
            } else {
                FeedbackTextEditor(text: $q2Text, placeholder: "Type your answer…")
                    .frame(height: 96)
            }
        }
        .padding(.top, 20)
    }

    private var card3: some View {
        VStack(spacing: 14) {
            QuestionTitle("Anything else you'd like to share?")
            Text("Optional — feel free to skip.")
                .font(.callout)
                .foregroundStyle(.secondary)
            FeedbackTextEditor(text: $q3Text, placeholder: "A thought, a wish, a gripe…")
                .frame(height: 96)
        }
        .padding(.top, 20)
    }

    private var thankYou: some View {
        VStack(spacing: 10) {
            Text("Thanks.")
                .font(.system(size: 36, weight: .semibold))
            Text("Your feedback helps make this better.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Behavior

    private func advance(to nextStep: Int) {
        // Hold the selection visible for a beat before the card slides away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation { self.step = nextStep }
        }
    }

    private func submit() {
        let q2Answer = q2Options != nil ? q2Choice ?? "" : q2Trimmed
        onSubmit(FeedbackResponse(
            submittedAt: Date(),
            satisfaction: satisfaction ?? 0,
            agentQuestionText: resolvedQuestion.questionText,
            agentQuestionRevision: resolvedQuestion.revision,
            agentAnswer: q2Answer,
            openEndedAnswer: q3Trimmed.isEmpty ? nil : q3Trimmed
        ))
        withAnimation { step = totalQuestions }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { dismiss() }
    }
}

// MARK: - Subviews

private extension View {
    func prominentLarge() -> some View {
        buttonStyle(.borderedProminent).controlSize(.large)
    }
}

private extension AnyTransition {
    static var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

private struct QuestionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= current ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

private struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: 42))
                .frame(width: 64, height: 64)
                .background(Circle().fill(isSelected ? Color.accentColor.opacity(0.18) : .clear))
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct OptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

/// TextEditor with a placeholder overlay — macOS SwiftUI doesn't ship one.
private struct FeedbackTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .padding(6)
                .scrollContentBackground(.hidden)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.22), lineWidth: 1))
    }
}
