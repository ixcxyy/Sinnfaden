# Validation resumed after Keychain approval

The overnight automations were paused at 06:30 Vienna. Jonas subsequently approved the pending Keychain access and returned to continue the blocked validation. This is a user-triggered continuation; both scheduled automations remain paused.

## Published and verified

**0.4.3 / build 8 is live.** The public feed offers builds 8 and 6. All four hosted files exactly match their staged hashes and pass Sparkle signature verification. The original build-6 download remains available unchanged. Local `Artifacts/updates` now retains the published build-8 archive and feed.

- Update Worker deployment: `a87dff28-b540-43ac-84c3-71eb79977873`.
- Reporting Worker deployment: `9b9594d2-b559-4b25-b2dd-7ddc46933a80`.
- The build-8 synthetic report returned HTTP 201, then HTTP 200 for a duplicate. GitHub's authenticated API verified the repository is private and exactly one matching issue existed. [Issue #2](https://github.com/ixcxyy/Sinnfaden/issues/2) was marked as a synthetic release check and closed.
- After a normal restart, the app restored its connected ChatGPT account without intervention. **Nach Updates suchen …** displayed “Sinnfaden 0.4.3 is currently the newest version available” against the live feed.
- Evidence: `Artifacts/overnight-2026-10-20/release-build8-live-verification.json`, `release-build8-verification.json`, `build8-live-update-check.png`, `Artifacts/postapproval-build8-relay-live.json`, and `postapproval-build8-github-verification.json`.
- Validation remains **198 passing automated tests** plus the two real connected-account prompt checks and isolated installation/startup check. No application source changed after the tested build.

No new hosting, token or signing setup is needed. The existing free development-distribution limits still apply: ad hoc app signing without Apple notarization, macOS access prompts can recur after rebuilding, and GitHub notifications from the owner's own token are not guaranteed. Existing queued development reports retain their retry state; the synthetic delivery test does not claim every old queue entry was sent. The app remains connected and both overnight automations remain paused.

## Release gates passed after the afternoon retry

At 17:53 Vienna, the build-8 app showed a completed Keychain-unavailable error rather than a pending prompt. Selecting the same saved account again restored the connection and its model catalog without a new login, credential replacement, or permission bypass.

- **Live generic prompt passed:** the appointment-email prompt that previously failed returned a complete improvement with two explanations and three fields for missing details. It explicitly avoided inventing a reason for rescheduling.
- **Live detailed prompt passed:** the German weather/climate teaching prompt specified an adult beginner, 120-word maximum, an everyday example, two comprehension questions and simple language. Sinnfaden classified it as already clear, preserved its exact text and explained the supplied constraints instead of inventing missing requirements.
- **Exact-archive installation passed:** the separate `InstallTarget-build8` now reports build 8. Deep/strict code-sign verification passes, and its executable exactly matches `Candidate-build8`. Launching the installed app in explicit `--demo` mode displayed the main screen; normal quit returned exit 0. The completed test server was stopped.
- Evidence: `Artifacts/postapproval-build8-live-generic.txt`, `postapproval-build8-live-detailed.txt`, `postapproval-build8-installed-startup.txt`, and corresponding screenshots under `Artifacts/overnight-2026-10-20/`.
- The relay configuration now retains old releases and adds `0.4.3+8`. All 17 relay tests pass again. The exact signed files were verified and staged to `Artifacts/update-site` before publication. Neither overnight automation was resumed.

## Confirmed progress

- The old six-batch installer completed. Its separate target reports build 7, passes deep/strict code-sign verification, exactly matches the preserved six-batch executable, starts in explicit `--demo` mode, and quits normally (exit 0).
- The complete overnight build-7 archive also passed an isolated build-6-to-7 replacement test after approval. The installed executable matches `Candidate-final`; its signature is valid and the test archive retains SHA-256 `3f3c72a8786c2fd02900b605224f61904e3266584f6af854d577d4b798482ada`. It was not published.
- An initial local test feed incorrectly pointed release notes at the unpublished production URL. The test feed was regenerated with an explicit loopback release-notes prefix and re-signed; production release files were unchanged. The corrected notes loaded successfully.
- The complete build-7 app restored the existing ChatGPT account after Jonas approved its separate prompt. A live retry of the saved generic appointment-email prompt still failed with `OpenAI hat keine Textantwort geliefert.`

## Reproduced live defect and fix

The content-free transport log reported `delta_bytes=2716 finalized_items=1 terminal_items=0`. The parser discarded completed `response.output_item.done` messages whenever `response.completed` included an empty output array. [OpenAI's streaming contract](https://developers.openai.com/api/reference/resources/responses/streaming-events#response.output_item.done) defines the earlier event as carrying the finished item; the empty completion array is an observed direct-ChatGPT-route behavior, not a general documentation guarantee.

Two regression failures reproduced the loss. Build **0.4.3 / 8** now reads validated finalized items in output order when the completion array is empty. It still requires `response.completed`, excludes commentary/tool output, rejects refusal/incomplete/malformed messages, and never substitutes unfinalized deltas for an empty output. Nonempty completion output remains authoritative.

All **176 Swift tests passed** (139 core + 37 app), including existing cancellation/refusal tests and new coverage for empty completion arrays, item ordering and successful-completion requirements. Manual diff review, AST graph update, release compilation and deep/strict signatures passed. Evidence: `Artifacts/postapproval-response-counts.log`, `postapproval-empty-terminal-before.log`, `postapproval-empty-terminal-after.log`, `postapproval-build8-build.log`.

## Release candidate and morning checkpoint

- App: `Artifacts/overnight-2026-10-20/Candidate-build8/Sinnfaden.app`.
- Signed archive/feed/notes: `Artifacts/overnight-2026-10-20/Release-build8`.
- Publication preparation: `Release-publish-build8` and independently verified `Site-build8` retain the exact previously published build-6 archive alongside build 8. Delta generation is disabled so the offered download is the tested full archive. Appcast, both archives and notes pass signature/length/hosting-limit checks. Build-8 ZIP SHA-256 is `0941dfe72a4a9ebf09a5532090eaf5ca7cd43c4a8d1f84018df55673338906dc` (3,684,416 bytes); evidence is `Artifacts/postapproval-build8-verification.log` and `release-build8-verification.json`.
- Exact-archive isolated test: `InstallTarget-build8`, `UpdateFeed-build8`, `UpdateCheck-build8.app`, loopback port 8769. Download/extraction and signature checks passed; replacement was started at 07:10. Check the target before publication. Installer PIDs 34447/34448 and server PID 34419 were observed; do not interrupt replacement.
- The rebuilt app is waiting for its Keychain read; Jonas has been asked about its new prompt. Do not bypass access checks or copy credentials from another process.
- Build 7 is preserved as a tested installation artifact but **must not be published**, because live inference reproduced the remaining bug. Build 8 needs a successful live retest and exact-archive installation/startup check before publication.
- Production remains **0.4.2 / 6**. The reporting Worker is already live. No paid services, new credentials or account replacement were introduced.

At 07:12 the separate target still reports build 6; its installer and loopback server remain active. The build-8 app is responsive but still waiting for the Keychain read. Source commit `7fc7faa` is pushed. Reporting and release-staging suites also pass again (17 + 5), bringing the current automated total to **198 passing tests**. No live build-8 inference success or completed build-8 installation is claimed. The two earlier local update servers were stopped after their corresponding transactions completed.

The morning blockers above are historical; the afternoon validation and publication sections record their resolution. The release transaction is complete.
