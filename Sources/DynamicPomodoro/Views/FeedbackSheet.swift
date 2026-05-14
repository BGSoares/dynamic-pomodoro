import SwiftUI

/// Three-question feedback prompt shown once per user, after they've
/// completed enough focus sessions to have formed an opinion.
///
/// Card flow:
///   0 → Q1 satisfaction emoji scale (fixed — longitudinal anchor)
///   1 → Q2 dynamic question authored by the routine review agent
///        (Resources/feedback_question.json — see AGENT_README.md)
///   2 → Q3 optional "anything else" free-text (fixed)
///   3 → Thank-you state, auto-dismisses
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let question: FeedbackQuestion?
    let onSubmit: (FeedbackResponse) -> Void

    @State private var step: Int = 0
    @State private var satisfaction: Int? = nil
    @State private var q2Choice: String? = nil
    @State private var q2Text: String = ""
    @State private var q3Text: String = ""

    private let totalQuestions = 3
    private let emojis = ["😖", "😕", "😐", "🙂", "😍"]

    /// Falls back to a generic open-ended Q2 if the JSON failed to load —
    /// the user still gets a coherent flow rather than a broken card.
    private var resolvedQuestion: FeedbackQuestion {
        question ?? FeedbackQuestion(
            questionText: "What's one thing about Dynamic Pomodoro you'd improve?",
            type: .openEnded,
            options: nil,
            revision: nil
        )
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
        HStack {
            // Left spacer balances the Skip button so the dots sit centered.
            Color.clear.frame(width: 56, height: 1)
            Spacer()
            ProgressDots(current: min(step, totalQuestions - 1), total: totalQuestions)
            Spacer()
            if step < totalQuestions {
                Button("Skip") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            } else {
                Color.clear.frame(width: 56, height: 1)
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

    private var footer: some View {
        HStack {
            if step > 0 && step < totalQuestions {
                Button(action: { withAnimation { step -= 1 } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
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

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case 0:
            // Auto-advance on emoji tap — no Next button needed.
            EmptyView()
        case 1:
            if resolvedQuestion.type == .multipleChoice {
                EmptyView()   // auto-advances on option tap
            } else {
                Button("Next") { withAnimation { step = 2 } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(q2Text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        case 2:
            let trimmed = q3Text.trimmingCharacters(in: .whitespacesAndNewlines)
            Button(trimmed.isEmpty ? "Skip" : "Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        default:
            EmptyView()
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
                        action: { selectSatisfaction(i + 1) }
                    )
                }
            }
        }
        .padding(.top, 28)
    }

    @ViewBuilder
    private var card2: some View {
        let q = resolvedQuestion
        VStack(spacing: 22) {
            QuestionTitle(q.questionText)
            if q.type == .multipleChoice, let opts = q.options, !opts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(opts, id: \.self) { opt in
                        OptionButton(
                            label: opt,
                            isSelected: q2Choice == opt,
                            action: { selectQ2Choice(opt) }
                        )
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

    private func selectSatisfaction(_ value: Int) {
        satisfaction = value
        // Hold the selection visible for a beat so the user sees confirmation
        // before the card slides away — feels less abrupt than instant-advance.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation { step = 1 }
        }
    }

    private func selectQ2Choice(_ option: String) {
        q2Choice = option
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation { step = 2 }
        }
    }

    private func submit() {
        let q = resolvedQuestion
        let q2Answer: String
        switch q.type {
        case .multipleChoice:
            q2Answer = q2Choice ?? ""
        case .openEnded:
            q2Answer = q2Text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let q3Trimmed = q3Text.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = FeedbackResponse(
            submittedAt: Date(),
            satisfaction: satisfaction ?? 0,
            agentQuestionText: q.questionText,
            agentQuestionRevision: q.revision,
            agentAnswer: q2Answer,
            openEndedAnswer: q3Trimmed.isEmpty ? nil : q3Trimmed
        )
        onSubmit(response)
        withAnimation { step = totalQuestions }   // → thank-you
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            dismiss()
        }
    }
}

// MARK: - Subviews

private extension AnyTransition {
    /// Cards slide in from the right, out to the left — matches the
    /// left-to-right progression of the step counter.
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
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
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
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
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
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : Color.secondary.opacity(0.06))
            )
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
        )
    }
}
