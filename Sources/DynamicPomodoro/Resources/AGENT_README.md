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
