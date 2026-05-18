# Routine review agent — read this

You're the agent that reviews Dynamic Pomodoro user feedback and deliberates improvements. The in-app feedback flow asks three questions. **Question 2 is yours to set.** Q1 and Q3 are fixed.

## Your file

→ **[`feedback_question.json`](feedback_question.json)** (this directory)

Edit it to change Q2. The app reads the file on every Idle-screen visit; changes go live on the next `swift run` (the JSON is a bundled resource, so the build needs to copy it into the new binary).

## What you can change

| Field | What it does |
|---|---|
| `question_text` | The prompt shown to the user (≤ 80 chars) |
| `type` | `"multiple_choice"` or `"open_ended"` |
| `options` | 2–5 strings, ≤ 24 chars each. **Required** for `multiple_choice`, **omit** for `open_ended` |
| `_revision` | Bump every time you change anything — tags the response so future-you can trace which question yielded what |

## Writing the question

The user sees Q2 with **no surrounding context**: just one sentence on a card. Most features in this app have **no agreed user-facing name** — internal labels like "reminder quote", "skip nudge", "idle stats footer" mean nothing to them. So:

- **Name the feature by what the user actually sees**, not by its code name. Don't say "the reminder quote" — say "the short italic line shown above the activity during breaks".
- **Anchor it to where and when it appears**: which window/screen, at what stage of the flow (idle, focus, break, post-skip, etc.). The user can't rate a feature they can't locate in their memory.
- **Quote a concrete example** when the feature is text-based and short — one short example resolves ambiguity faster than two sentences of description.
- **If you can't fit all that in ≤ 80 chars**, the question is too granular for Q2. Pick a narrower scope or ask about the overall behavior instead. Don't ship an ambiguous prompt.
- **Avoid jargon from `PURPOSE.md` / the spec** — those are author-facing terms. The user only knows what they've seen on screen.

Quick check before saving: would a user who skimmed the app once know exactly what you're asking about? If not, rewrite.

## What you must not change

- **Q1** — satisfaction emoji scale (😖 😕 😐 🙂 😍). Fixed, longitudinal anchor. Hard-coded in [`../Views/FeedbackSheet.swift`](../Views/FeedbackSheet.swift).
- **Q3** — optional free-text "Anything else?". Fixed.
- **The schema.** No new top-level fields. The Swift decoder rejects unknown shapes.
- **`_INSTRUCTIONS_FOR_ROUTINE_AGENT`.** Leave it as-is so the next agent finds it.

## Where responses live

User answers append to this file on the user's machine:

```
~/Library/Application Support/DynamicPomodoro/feedback.json
```

One JSON record per submission. Each record carries `agentQuestionText` and `agentQuestionRevision` so you can attribute answers to the version of Q2 you authored.

## Sanity checklist before saving

- [ ] `question_text` is under 80 characters
- [ ] For `multiple_choice`: every option is under 24 characters
- [ ] You bumped `_revision`
- [ ] The JSON parses (try `jq . feedback_question.json`)
- [ ] You did not touch Q1, Q3, or the schema
