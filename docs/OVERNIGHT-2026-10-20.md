# Overnight improvement checkpoint

## Authorized scope and deadline

Jonas asked for sustained work until **20 October 2026, 06:30 Europe/Vienna (04:30 UTC)**. Preserve the current visual design. Focus on backend reliability, prompt output quality, learning value, efficiency, and reproduced bugs. Small useful features are authorized, as are private GitHub pushes and a tested signed app update. Keep hosting free and do not switch to paid API usage. Use the existing connected ChatGPT account only for bounded synthetic app-quality checks; preserve its session and all user data.

Claude may be used through its Mac app for necessary design work with a focused brief. If it reaches a usage limit, leave a precise handoff and continue independently. No design work is currently needed. Do not redesign or casually adjust styling.

## Scheduled continuation

- Heartbeat `sinnfaden-overnight-improvements`: every 15 minutes, ending at 04:30 UTC.
- Heartbeat `sinnfaden-morning-handoff`: one final run at 06:30 local time.
- At 06:00, stop adding scope and prioritize tests, review, release, actual update installation and documentation. At 06:30, stop new edits, finish any already-running publication transaction safely, report actual results, and pause both automations.
- An idle-sleep prevention process was started for this night. The Mac must remain powered with lid open and Codex running. Do not promise execution while the machine is asleep or disconnected.

## Starting state

- Private repository: `ixcxyy/Sinnfaden`, branch `main`, clean at `e2e563d1de7b4ed06b9b1aed56ffdc1851e63d6c`.
- Current published app: **0.4.2 / build 6**, free ad hoc distribution, signed Sparkle feed/archives. Project private signing key is in the login Keychain under `at.klar.promptcoach`; never export it.
- Live bug relay and static update host on Cloudflare Free. See `docs/FREE-HOSTING.md` for exact release commands and limitations. GitHub token stored only in the relay secret.
- Private setup issue #1 proved delivery, duplicate grouping, and the production Swift client's acknowledgement; marked synthetic and closed.
- The owner's current app has automatic reporting and update checks enabled. Existing local reports stay local.
- Previous validation: 89 Swift tests, 13 relay tests, 5 release-staging tests; actual update installation/relaunch from build 5 to 6 passed.
- Existing app UI includes annotations, editable generated inputs, comparison, practice, six lessons, follow-up prompts, recipes, and persistent per-account learning state.

## Work plan and checkpoints

1. Run the baseline test suite and bounded synthetic live prompt checks. Examine concrete failures without logging credentials or private user prompts.
2. Reproduce output/validation and learning-feedback defects with failing local regression tests, then fix them. Prioritize honest, useful explanations over generic praise or keyword-only success claims.
3. Inspect account transitions, cancellation, saving and comparison state for data loss, stale output, or wasted requests.
4. Improve a small learning behavior only where the current behavior has a demonstrated gap; keep the visual structure unchanged.
5. Review and test each batch; update this document with evidence and next steps. Keep separate release notes for user-visible changes.
6. Publish a new version only after validation; never replace an existing signed archive with different bytes. Push reviewed source to GitHub, deploy the relay release allowlist and signed static update feed, and prove installation on a separate app copy without altering the owner's draft.

## Current observations (00:34 Vienna)

- `README.md` now correctly documents the active reporting/update endpoints and links to free-hosting instructions.
- Learning feedback uses deliberately limited local rules. Investigate incorrect task-success classifications (negation, wrong correction direction, unrelated numbers, and incomplete answers) with concrete cases.
- The app recorded local `coach / invalidResponse` reports while the owner tried new prompts. Determine whether the live generation pipeline reproduces failures before weakening any validation.
- Applied skill: `/Users/jonas/.agents/skills/ai-regression-testing/SKILL.md`; tests should target observed failures and compare live/runtime behavior against mocked assumptions.

## Completed this night

First batch passed local diff review, all 103 tests, release compilation, and deep/strict app signature verification. It was pushed to private `main` as **709e07d**; no new app update has been published. Version **0.4.3 / build 7** is reserved in `Config/Info.plist`.

- Placeholder filling now preserves exactly what the user typed, never interprets inserted text as another field, and handles placeholders split across annotated segments. Invalid field tokens cannot replace ordinary words. Reproduced eight failing assertions before the fix.
- Format lessons now distinguish output length from unrelated numbers and handle explicit alternatives. Checking lessons reject reversed day corrections, changed times, and requests not to correct the day. Reproduced nine failing assertions and retained the original exercise guidance for uncertain answers.
- The response stream retains finalized output items when the completion envelope omits them, excludes commentary from final tutor JSON, and rejects explicit empty or malformed completion output. Refusals cannot become partial successes. No-text diagnostics contain only numeric counts.
- Malformed optional annotations, fields, or exercises no longer discard an otherwise valid prompt and independently valid sibling metadata. Required prompt content still passes strict validation.
- Credential reads now run off the main thread and cooperative executor. Account selection ignores late results from a previously selected account. Cancellation prevents delivery of late credentials. Storage permissions and credential contents are unchanged.
- Baseline: 89 Swift tests passed. Latest full run: **103 tests passed** at 00:04. The malformed-stream regression reproduced three failures before its fix. Logs are under `Artifacts/overnight-*.log`.

Second batch, pushed as **a5af6cb**: malformed required prompt segments now fail validation rather than disappearing from the returned prompt; explicit unsupported schema versions are not silently rewritten; unused malformed clarification metadata is ignored, while a required clarification must remain valid. Seven assertions failed before these fixes; **106 Swift tests passed** afterward (`overnight-content-before.log`, `overnight-content-after.log`). Existing pipeline tests verify that validation failure triggers at most one announced repair and preserves the original input.

Third batch, pushed as **52fd549** (00:16): reproduced and fixed two cancellation defects. A cancelled waiter must not receive the shared credential-refresh result, while shared token rotation is allowed to finish safely. Cancellation during delivery of a terminal stream message must throw instead of returning a successful result. Added cancellation boundaries before inference and after transport completion. **108 Swift tests passed** (`overnight-cancellation-before.log`, `overnight-cancellation-after.log`). Coach/follow-up requests now capture their starting model for any format repair and reject stale account results, as do comparison callbacks. This account/model binding was code-reviewed and compiled; no live account-switch test is claimed. History entries have no model field, so the earlier suspected incorrect recorded-model bug does not apply.

Fourth batch, pushed as **048db41** (00:20): lesson checks now exclude nearby explicit negation for goal, context, audience/tone, and follow-up evidence; valid alternatives introduced by `sondern` still work. A relative start time (`ab morgen`, `ab dem nächsten Montag`) is no longer counted as a walking start location. Context and audience feedback identifies the missing requirement. Twelve failing assertions reproduced these cases, and **110 Swift tests passed** after fixes (`overnight-lesson-negation-before.log`, `overnight-location-before.log`, `overnight-lesson-negation-after.log`). These remain bounded local rules, not general semantic grading. The complete four-batch candidate was rebuilt; no new design work was needed.

Fifth batch (00:34): generated form answers were never stored in history; reopening a prompt lost them. Two different entries with equal responses could also leak the currently displayed answers into each other. Three new application-state tests reproduced **nine failed assertions**. Answers now persist per entry, deliberately cleared suggestions remain cleared, older history still decodes, and manual edits keep priority. History previews/search and exports use the saved values without rewriting the original response or annotations. Field editing no longer reloads/decodes the entire history on every keystroke. The new `KlarAppTests` target uses a temporary storage root and in-memory empty registration; no owner data, Keychain access, or live inference is involved. **115 tests passed** (112 core + 3 app; `overnight-field-persistence-before.log`, `overnight-field-persistence-after.log`, `overnight-persistence-all-tests.log`). Full release compilation, deep/strict app signature verification, diff review and graph update passed. No design sources changed.

### Native UI check

The complete two-batch candidate was built and signature-verified. An isolated copy at `Artifacts/overnight-2026-10-20/Sinnfaden QA.app`, bundle ID `at.klar.promptcoach.overnightqa`, was run with `--demo`. No live account requests were made. The existing demonstration account, separate from the owner's account, received two clearly synthetic lesson attempts.

- Opened Form und Länge wählen through the existing learning navigation.
- Submitted `Bitte als Tabelle. Der Text handelt von drei Personen.` The app correctly showed `Noch nicht ganz` and explained that content counts do not set output length.
- Revised directly to `Bitte keine Tabelle, sondern drei kurze Stichpunkte.` The app enabled checking and showed `Das passt zur Aufgabe` with the appropriate independent-attempt caveat.
- Opened the takeaway, quit normally, relaunched with `--demo`, and confirmed the learning path retained completion (1 of 6; format lesson marked `Geschafft`). Quit the QA copy normally afterward.
- Screenshot: `Artifacts/overnight-2026-10-20/lesson-specific-feedback.png`. No view, layout, color, animation, or design source was changed.

### Live validation blocker and candidate state

- The original installed app reproduced `OpenAI hat keine Textantwort geliefert.` on a generic appointment-email prompt. The stream fixes are regression-tested but have **not** yet been proven against the connected account.
- A rebuilt first candidate (0.4.3/build 7) at `Artifacts/Sinnfaden.app` is waiting for macOS Keychain permission. Process sampling confirmed `SecItemCopyMatching` on the main thread. PID 69498 is that old candidate; it does not yet contain the subsequent asynchronous-read or sanitizer fixes. Rebuild before final validation/release.
- The complete five-batch candidate is built separately at `Artifacts/overnight-2026-10-20/Candidate/Sinnfaden.app`. The two-batch UI was checked through the isolated demo copy; later changes have automated tests and a release build. No candidate has been tested against the real account. The first frozen candidate was not overwritten.
- A user question asking them to approve Sinnfaden's macOS Keychain dialog is pending. Do not bypass permissions, extract tokens elsewhere, or treat silence as approval. The command-line live suite was stopped before inference; `Artifacts/live-coach-suite.json` is stale from October 18, not evidence for tonight.
- The owner's draft was saved before the old app quit. A verified previous app copy is preserved at `Artifacts/overnight-2026-10-20/Previous/Sinnfaden.app`; do not overwrite it. Use an isolated copy for the build 6 → 7 update installation test.
- Next: preserve the five completed batches and inspect persistence failure behavior when changing accounts, response comparison fidelity, and update publication/installation tooling. The first listed cancellation, model-binding, lesson-negation and field-persistence leads are handled above; do not redo them. `LearningWorkspace.switchAccount` currently clears state after a failed flush, and history navigation can discard unsaved entry changes after an actual write failure. Use the new isolated app-test target to reproduce and keep failed saves recoverable per account; never display the old account's work under the new account. Avoid adding broad language heuristics without a demonstrated case.
- Update-test preparation: the earlier harness source is `Artifacts/free-hosting-validation/UpdateCheck.m`. Sparkle's installed `SPUUpdaterDelegate.h` supports `feedURLStringForUpdater:` for a localhost-only signed test feed, and `updaterShouldRelaunchApplication:` can return NO so installation does not trigger real-account login; the installed app can then be launched explicitly with `--demo`. Test the exact candidate archive on a copy of preserved build 6 before publishing, verify signatures/version, and then publish a signed feed pointing to the HTTPS host. Keep test feeds/archives isolated from immutable production `Artifacts/updates`. No new installation test has run yet.
- Retry live prompt quality checks only after the permission obstacle is resolved. Add `0.4.3+7` to the relay allowlist before publication; current live versions are `0.4.1+5,0.4.2+6`. New version publication and a real build 6 → 7 installation test remain outstanding. No changes to the live relay or feed were made during this first overnight checkpoint.

## Claude handoff

None; current scope does not require design changes.
