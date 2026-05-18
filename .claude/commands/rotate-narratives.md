---
description: Rotate stale cycling history/wisdom narratives based on display counts
---

Check how often each `history_*` / `wisdom_*` activity has been shown to the user and replace any that have hit the staleness threshold with fresh narratives in the same voice.

## Steps

1. **Locate the session log.** It lives at `~/Library/Application Support/DynamicPomodoro/sessions.json` on the user's Mac. If the path doesn't exist in this environment (e.g. running in a cloud container), ask the user to attach or paste the file's contents, or to run this command locally instead. Don't fabricate counts.

2. **Count displays per narrative.** The log is a JSON array of entries with `activityID`. Count occurrences of each `activityID` that starts with `history_` or `wisdom_` (consider both `breakCompleted` and `breakSkipped` kinds — the narrative was displayed in either case). Print the table of counts for context.

3. **Decide what to rotate.** For each narrative with count >= 5, mark it for replacement. If none meet the threshold, report the counts and exit without changes.

4. **Generate replacements.** For each retired narrative, write a new entry in the same terse, factual, evocative voice as the existing ones in `Sources/DynamicPomodoro/Resources/activities.json`. Prefer concrete moments over generalities — a specific year, climb, rider, or quote. Do not duplicate any existing narrative (check both the current `activities.json` and the staleness list).

   For each new entry:
   - `id`: snake_case, descriptive (e.g. `history_hinault_1985`, `wisdom_anquetil`)
   - `name`: short, like "1985, La Vie Claire" or "Jacques Anquetil"
   - `instruction`: 1–3 sentences, no questions, no "sit with it" — just the story or quote, landing on a quiet reflection
   - `category`: `inspiration`
   - `band`: `short`
   - `energy`: `gentle`
   - `suitable_times`: copy from the entry being replaced

5. **Apply the edit.** Replace the retired entries in `activities.json` in place (preserve ordering — the new entry takes the old entry's slot).

6. **Report.** Show a diff-style summary: which IDs were retired (with their display counts), which IDs replaced them, and a one-line preview of each new instruction.

7. **Don't commit or push.** Leave the working tree dirty so the user can review and edit before committing.

## Notes

- The current library has 6 narratives: `history_lemond_fignon_89`, `history_pantani_galibier`, `history_voigt_hour_record`, `wisdom_merckx`, `wisdom_pantani`, `wisdom_voigt`. The cycling canon is deep — Coppi, Bartali, Anquetil, Hinault, Indurain, Armstrong-era drama, modern Pogačar/Vingegaard duels, classics moments (Roubaix, Flanders), track records, and so on are all fair game.
- Threshold of 5 is intentional: enough exposure that the user has internalized the story, not so high that the rotation never triggers.
- The voice in existing entries is the target — match it precisely.
