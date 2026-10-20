# Validation resumed after Keychain approval

The overnight automations were paused at 06:30 Vienna. Jonas subsequently approved the pending Keychain access and returned to continue the blocked validation. This is a user-triggered continuation; both scheduled automations remain paused.

## Confirmed progress

- The old six-batch installer completed. Its separate target reports build 7, passes deep/strict code-sign verification, exactly matches the preserved six-batch executable, starts in explicit `--demo` mode, and quits normally (exit 0).
- The complete overnight build-7 archive also passed an isolated build-6-to-7 replacement test after approval. The installed executable matches `Candidate-final`; its signature is valid and the test archive retains SHA-256 `3f3c72a8786c2fd02900b605224f61904e3266584f6af854d577d4b798482ada`. It was not published.
- An initial local test feed incorrectly pointed release notes at the unpublished production URL. The test feed was regenerated with an explicit loopback release-notes prefix and re-signed; production release files were unchanged. The corrected notes loaded successfully.
- The complete build-7 app restored the existing ChatGPT account after Jonas approved its separate prompt. A live retry of the saved generic appointment-email prompt still failed with `OpenAI hat keine Textantwort geliefert.`

## Reproduced live defect and fix

The content-free transport log reported `delta_bytes=2716 finalized_items=1 terminal_items=0`. The parser discarded completed `response.output_item.done` messages whenever `response.completed` included an empty output array. [OpenAI's streaming contract](https://developers.openai.com/api/reference/resources/responses/streaming-events#response.output_item.done) defines the earlier event as carrying the finished item; the empty completion array is an observed direct-ChatGPT-route behavior, not a general documentation guarantee.

Two regression failures reproduced the loss. Build **0.4.3 / 8** now reads validated finalized items in output order when the completion array is empty. It still requires `response.completed`, excludes commentary/tool output, rejects refusal/incomplete/malformed messages, and never substitutes unfinalized deltas for an empty output. Nonempty completion output remains authoritative.

All **176 Swift tests passed** (139 core + 37 app), including existing cancellation/refusal tests and new coverage for empty completion arrays, item ordering and successful-completion requirements. Manual diff review, AST graph update, release compilation and deep/strict signatures passed. Evidence: `Artifacts/postapproval-response-counts.log`, `postapproval-empty-terminal-before.log`, `postapproval-empty-terminal-after.log`, `postapproval-build8-build.log`.

## Current release candidate

- App: `Artifacts/overnight-2026-10-20/Candidate-build8/Sinnfaden.app`.
- Signed archive/feed/notes: `Artifacts/overnight-2026-10-20/Release-build8`.
- Exact-archive isolated test: `InstallTarget-build8`, `UpdateFeed-build8`, `UpdateCheck-build8.app`, loopback port 8769. Download/extraction and signature checks passed; replacement was started at 07:10. Check the target before publication. Installer PIDs 34447/34448 and server PID 34419 were observed; do not interrupt replacement.
- The rebuilt app is waiting for its Keychain read; Jonas has been asked about its new prompt. Do not bypass access checks or copy credentials from another process.
- Build 7 is preserved as a tested installation artifact but **must not be published**, because live inference reproduced the remaining bug. Build 8 needs a successful live retest and exact-archive installation/startup check before publication.
- Production remains **0.4.2 / 6**. The reporting Worker is already live. No paid services, new credentials or account replacement were introduced.

Next: verify build-8 Keychain restoration, retry the generic prompt and a bounded set of synthetic tasks, complete the installation/startup check, then publish only the exact tested archive with the previous published release retained. Keep user work and the existing account intact.
