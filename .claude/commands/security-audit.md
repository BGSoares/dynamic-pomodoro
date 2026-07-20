---
description: Investigate the app for security risks specific to its threat model
---

Investigate this codebase for security risks that actually matter for *this* app — a local, single-user, native macOS menu-bar tool that ships via Sparkle. Skip generic web/OWASP boilerplate that doesn't apply.

## Read first, before opening any source file

1. [`PURPOSE.md`](../../PURPOSE.md) §6 — "Local, private, native." Nothing leaves the machine. Use this as the invariant under audit: a finding is real if it could violate it.
2. [`README.md`](../../README.md) — architecture map, Sparkle setup, release flow, what is *not* built (no accounts, no cloud, no network beyond updates).
3. [`Entitlements.plist`](../../Entitlements.plist) — the sandbox / hardened-runtime surface.

If a finding assumes a server, an account, an external API, telemetry, cross-user data, or a feature on the README "Not built" list, drop it. Those threat models don't exist here.

## Threat model — what's actually in scope

The app's exposure is narrow. Audit these surfaces, in priority order:

1. **The update path (Sparkle).** This is the single largest risk: it executes code from the internet.
   - [`Sources/DynamicPomodoro/Services/UpdaterService.swift`](../../Sources/DynamicPomodoro/Services/UpdaterService.swift) — feed URL, EdDSA verification, host app config (`SUFeedURL`, `SUPublicEDKey`), automatic-install behaviour.
   - [`build-app.sh`](../../build-app.sh) — how the public key is baked into `Info.plist`, how `CFBundleVersion` is set, whether anything from the build environment leaks into the bundle.
   - [`release.sh`](../../release.sh) — local signing path, where the private key comes from (Keychain), whether the script can be tricked into signing the wrong artifact.
   - [`.github/workflows/release.yml`](../../.github/workflows/release.yml) — `SPARKLE_ED_PRIVATE_KEY` handling, action pinning (tag vs SHA), `pull_request_target` / unsafe checkout patterns, `permissions:` block.
   - Appcast URL — is it HTTPS, does the redirect chain stay HTTPS, what happens on cert failure, what happens if the GitHub redirect target is attacker-controlled (private repo / typo-squatting).

2. **Local files the app reads or writes.**
   - `~/Library/Application Support/DynamicPomodoro/sessions.json` — does the writer validate path, follow symlinks, atomic-write, set sane permissions? Could another process on the same machine (which is in-scope only for a malicious helper / shared-mac case) inject content that crashes the parser or steers selection logic?
   - JSON decoding of bundled `Resources/activities.json` — fail-closed vs fail-open, behaviour on malformed JSON, behaviour on a swapped bundle resource (codesign should catch this; verify).
   - [`Sources/DynamicPomodoro/Models/SessionLog.swift`](../../Sources/DynamicPomodoro/Models/SessionLog.swift) and any other persistence in `Models/` — same questions.

3. **Sandbox and entitlements.**
   - `Entitlements.plist`: is `com.apple.security.app-sandbox` on? What entitlements are claimed, and is each one actually used? Network client entitlement *must* be present for Sparkle; anything beyond that needs justification.
   - Hardened runtime + notarization: is the release-built `.app` signed with hardened runtime, and does the workflow notarize? An un-notarized build is not a vulnerability per se but is a release-quality finding.

4. **Shell scripts and Swift codegen scripts.**
   - `build-app.sh`, `release.sh`, `generate-icon.swift`, `generate-toolbar-icon.swift` — unquoted variable expansions, `set -euo pipefail` discipline, `curl | sh` patterns, temp-file races, hard-coded paths under `/tmp`, anything that executes data as code.

5. **What's stored in `UserDefaults`.**
   - [`Sources/DynamicPomodoro/Models/Settings.swift`](../../Sources/DynamicPomodoro/Models/Settings.swift) — only the four documented settings should be there. Anything else (tokens, identifiers, paths) is a finding. UserDefaults is world-readable to any process running as the user; treat it as non-secret.

6. **Anything that opens a URL or runs a subprocess.**
   - `grep -rn "NSWorkspace\|Process(\|URL(string:" Sources/` — every external URL and every subprocess invocation is a question: is the input attacker-influenceable, and what's the worst case if it is.

7. **Notifications and screen lock.**
   - [`Sources/DynamicPomodoro/Services/NotificationService.swift`](../../Sources/DynamicPomodoro/Services/NotificationService.swift) and [`Sources/DynamicPomodoro/Services/ScreenLockService.swift`](../../Sources/DynamicPomodoro/Services/ScreenLockService.swift) — what API is used to lock the screen (private API, AppleScript, `CGSession`?), what permissions does it implicitly require, what content is rendered into notification bodies.

## Out of scope — do not report findings about

- Missing input validation on data that is hardcoded in the bundle (`activities.json` is shipped with the app; the threat model is "attacker replaced the bundle," which is the codesign question, not a parser-validation question).
- "Add rate limiting," "add audit logging," "add a CSRF token" — there is no server, no multi-user surface, no session cookie.
- "Use a secret manager" — there are no app-side secrets to manage. The Sparkle private key lives in CI (`SPARKLE_ED_PRIVATE_KEY`) and a maintainer's Keychain; that *is* the secret manager.
- "Encrypt sessions.json at rest" — FileVault already does this. Adding app-layer crypto for one user's data on their own disk is ceremony.
- Anything about adding telemetry, crash reporting, analytics, or A/B infrastructure for security purposes.
- Findings whose only mitigation grows the surface area (PURPOSE §5). If the cure violates the constitution, the disease isn't a finding.

## Steps

1. **Map the surface.** List every file under `Sources/DynamicPomodoro/Services/`, every `.sh` script, every workflow under `.github/workflows/`, every URL string in the codebase, and every file-system path written to. Spend ≤10 minutes here. Output it as a one-line-per-item map for context — this is the *whole* attack surface; if a finding doesn't trace back to an entry in it, the finding is speculative.

2. **Walk the update path end-to-end.** Compromise scenario: an attacker controls the network between the user and `releases/latest/download/appcast.xml`. What stops them? Verify each link in the chain: HTTPS, EdDSA signature check (`SUPublicEDKey` matches the private key in CI), Sparkle version (CVE history), automatic-vs-manual install setting, and whether the user is prompted before install. A break in any one of these is a P0 finding.

3. **Walk the release path end-to-end.** Compromise scenario: an attacker opens a PR. Can the workflow be made to sign and publish their code? Check `pull_request` vs `push` triggers, `permissions:`, action versions (pinned by SHA?), `secrets.SPARKLE_ED_PRIVATE_KEY` exposure, and whether the signing step runs only on tagged commits from protected refs.

4. **Audit the local-file surface.** For each read/write, ask: where does the path come from, is it under the user's Library / app-sandbox container, is the write atomic, does the decoder fail closed, are exceptions swallowed in a way that masks tampering. Symlink-following at write time is the specific shape to look for.

5. **Audit the entitlements.** Cross-reference `Entitlements.plist` against the code: every entitlement claimed must be exercised by code in this repo. Drop unused ones (that's a finding — least privilege).

6. **Audit the scripts.** Read `build-app.sh` and `release.sh` line by line for the classic shell footguns: unquoted `$VAR`, `eval`, `curl ... | sh`, `mktemp` vs `/tmp/foo-$$`, `set -e` discipline, secrets printed to logs.

7. **Rank.** Order findings by `(blast radius × likelihood) ÷ cost-of-fix`, descending. Cap at 10. A P0 update-path break beats five P3 "consider adding…" items.

## Output format

A single markdown report. No intro paragraph. Lead with a one-line verdict: `Verdict: <clean | minor findings | material findings | critical>`.

Then, for each finding:

```
### N. <file>:<line range> — <one-line label>  [P0|P1|P2|P3]

**Surface:** <which item from the threat-model map this lives on>
**Risk:** <one sentence: what an attacker achieves, under what assumption>
**Evidence:** <the specific code/config that shows it — quote the line, don't paraphrase>
**Fix:** <the smallest concrete change. If "no fix needed, document it," say so>
**Why this matters here:** <one sentence tying it to PURPOSE §6 or the update path; if you can't, it probably isn't a finding for this app>
```

Severity rubric (use it, don't invent your own):

- **P0** — remote code execution, signature bypass, supply-chain compromise of the release pipeline.
- **P1** — local privilege escalation on the user's Mac, ability to tamper with persisted data to alter app behaviour, secrets exfil from CI.
- **P2** — defence-in-depth gaps (missing hardened runtime, over-broad entitlements, unpinned actions) with no known exploit path.
- **P3** — hygiene (unused entitlement, swallowed error, shell script quoting). Include only if the fix is one line.

End with one line: `Summary: <N> findings (<P0>/<P1>/<P2>/<P3>). Highest unresolved: <P-level>.`

If the audit finds nothing material, say so plainly. A clean report with three P3 hygiene notes is a more useful artifact than a padded list of P2s invented to look thorough.

## Don't commit

This command produces a report. Leave the working tree clean. The user reads it, picks which items to fix, and addresses them by hand or in a follow-up session.
