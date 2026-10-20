# Sinnfaden 0.4.3 release verification

**Published: 20 October 2026, build 8.** The existing visual design is preserved. Source and release operations are pushed to private `ixcxyy/Sinnfaden`; signed downloads use the existing free Cloudflare service.

## Improvements

The overnight work corrected cancellation and account-switch races, saved field restoration, failed-save recovery, oversized input handling, generated-output validation, lesson feedback and report delivery. The post-approval live test exposed a further response-parser defect: a completed stream with an empty final envelope discarded its already finalized text. Build 8 preserves validated finalized items while retaining refusal, completion and malformed-response safeguards.

Two real ChatGPT-account tests passed. The generic appointment-email prompt produced useful missing-detail fields and explanations without inventing a reason. The detailed German weather/climate learning prompt was correctly recognized as already clear and preserved unchanged. These bounded checks establish that the reproduced failure is fixed; they do not guarantee every possible generated answer.

## Verification and exact release

- **198 automated tests passed:** 176 Swift (139 core + 37 app), 17 relay and 5 release-staging tests. Manual diff review and the local AST graph update completed for the source fix.
- App source commit: `7fc7faac36f8b2586f885e10c5f82b2d946658c1`. Subsequent changes are release configuration and documentation.
- Archive: `Sinnfaden-0.4.3-8.zip`, **3,684,416 bytes**, SHA-256 `0941dfe72a4a9ebf09a5532090eaf5ca7cd43c4a8d1f84018df55673338906dc`.
- A separate installed build 6 was updated through Sparkle to this exact archive. Its installed version is 8, deep/strict code-sign verification passes, and its executable matches the candidate. Explicit demo startup and normal quit passed.
- The public feed, two archives and release notes were downloaded after deployment. All four files match their staged bytes and pass signature verification. The original build-6 archive remains unchanged. No delta update is offered for build 8.
- The app restored its existing ChatGPT account after restart. Its **Nach Updates suchen …** command reported that 0.4.3 is the newest available version.
- A synthetic report created exactly one private GitHub issue; the duplicate was acknowledged without creating another issue. [Release test #2](https://github.com/ixcxyy/Sinnfaden/issues/2) was clearly marked and closed.

## Live services

- [Signed update feed](https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/appcast.xml)
- [Build-8 download](https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/Sinnfaden-0.4.3-8.zip)
- [Private bug inbox](https://github.com/ixcxyy/Sinnfaden/issues)
- Update deployment: `a87dff28-b540-43ac-84c3-71eb79977873`.
- Reporting deployment: `9b9594d2-b559-4b25-b2dd-7ddc46933a80`.
- Supported reporting releases: `0.4.1+5,0.4.2+6,0.4.3+8`.

## Limits and handoff

This is free **development distribution**: Sparkle-signed updates and ad hoc app signing, without Apple Developer ID/notarization. Rebuilding can trigger macOS Keychain access prompts; no protections were bypassed. The existing saved account recovered by selecting it again, without signing out or replacing credentials. GitHub email/push notification for issues created with the owner's own token is not guaranteed; the private issue inbox is the verified delivery destination. Reporting retry/backoff remains in effect for older queued development reports.

Updates require download/install confirmation. Automatic checks operate while the app is running and online. No hosting upgrade, paid API fallback, new token or new signing key was needed. Both overnight automations remain paused.

Build 7 was never published and must not be released: the live parser failure was fixed in build 8. Historical night checkpoints remain in [OVERNIGHT-2026-10-20.md](OVERNIGHT-2026-10-20.md). Detailed post-approval chronology and evidence paths are in [POST-APPROVAL-2026-10-20.md](POST-APPROVAL-2026-10-20.md). Operational instructions are in [FREE-HOSTING.md](FREE-HOSTING.md).
