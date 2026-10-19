# Backend bug hunt — 19 October 2026

Scope: direct OpenAI transport, token parsing, account transitions, local persistence failure paths, packaging, and the new reporting/update flow. This is a focused audit, not a guarantee that every bug has been found.

## Fixed

1. **Truncated text accepted as final output.** When streamed deltas differed from the completed response, the parser retained the partial text. The completed response is now authoritative. Regression test failed before the change and passes after it.
2. **Completed refusal accepted as partial success.** A refusal in the final response could leave earlier streamed text looking successful. The parser now rejects it. Reproduced with a failing test before fixing.
3. **Malformed token renewal accepted.** Empty/missing access tokens and boolean `expires_in` values could be treated as valid token responses, potentially replacing usable stored credentials. Renewal now requires a nonempty access token and a finite, positive numeric lifetime. Identity-only initial sign-in remains supported. Three failing cases now pass.
4. **Incorrect streaming MIME accepted.** Substring matching accepted values such as `application/x-text/event-stream-invalid`. Matching now uses the exact media type while retaining the previously verified missing-header behavior.
5. **Stale account work could continue after token refresh.** Model refresh and the structured capability probe now check the account revision before the next network request; the probe snapshots its selected model before awaiting.
6. **Unreadable history left a writable store attached.** The app now attaches a history store only after both draft and history have loaded successfully. It also refuses to replace an unsaved draft or claim successful deletion when the store is unavailable.
7. **API-key connection could appear saved when registration storage was unavailable.** It now stops before saving credentials in that state.
8. **Duplicate model IDs propagated into UI selection.** The available model list is deduplicated while preserving order.
9. **Untrusted server error strings written to public logs.** Coach logging now uses only fixed categories and numeric status, without server-supplied code strings or validation text. New bug reports use a strict field allowlist.
10. **Release version drift.** Packaging claimed 0.3.0 while settings claimed 0.4. The bundle now owns the displayed version (0.4.1/build 5), and the DMG filename reads it from the bundle.

## Added

See [maintenance and activation guide](MAINTENANCE.md) for the private GitHub issue relay, local review/export, opt-in reports, signed Sparkle updater, and release preparation.

## Validation evidence

- Four initial backend regression tests produced six assertion failures before the fixes; all pass after the fixes.
- Full Swift suite: **89 tests, zero failures**.
- Relay: **10 tests, zero failures**, including duplicate concurrency and recovery after an uncertain GitHub POST.
- Cloudflare Wrangler dry run succeeded; no deployment occurred. The actual local Worker runtime correctly returns a retryable 503 while unconfigured.
- Release app built for arm64 and passed deep/strict code-sign verification with the embedded Sparkle framework.
- Development DMG generated and verified.
- Native UI checked in an isolated demo bundle: version 0.4.1/build 5, new settings section, disabled unconfigured delivery controls, and an explicit “updates not configured” dialog.
- Screenshot: `Artifacts/Maintenance-settings.png`.

## Activation follow-up

Repository setup follow-up: the user supplied [ixcxyy/Sinnfaden](https://github.com/ixcxyy/Sinnfaden), verified private with Issues enabled. The working folder now has that Git origin, and the relay configuration targets it. No diagnostic issue has been sent.

The relay and static update host are now deployed on Cloudflare Free, and a project-specific Sparkle key is in the Mac Keychain. Version 0.4.2/build 6 is published with signed archives and feed. GitHub token setup and live delivery verification are still pending. Apple signing/notarization remains intentionally unconfigured. See [free hosting operations](FREE-HOSTING.md) for current setup and verification. The user’s live ChatGPT connection was not used for test requests or signed out.

Reports cover handled errors, not native crash dumps. A report identifies a technical failure group and app build, but does not automatically provide reproduction steps or fix code. Review and validation remain required before releasing a patch.
