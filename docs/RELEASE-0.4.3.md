# Sinnfaden 0.4.3 release handoff

**Superseded candidate:** after Jonas approved Keychain access, live validation reproduced a remaining stream-handling defect in build 7. Build 8 contains its regression-tested fix and is undergoing live/installation checks. Do not publish the build-7 archive described below. See [the post-approval validation record](POST-APPROVAL-2026-10-20.md) for current status. The following is the preserved overnight handoff.

**Verified 20 October 2026, 05:17 Europe/Vienna. Unpublished.**

Final status check at **06:26 Vienna**: the separate installation target remains build 6, the installer remains stalled, and this package is still unpublished. All subsequent commits after package preparation change documentation only. The night ends at 06:30 with no further source edits; the installed/published update and connected-account quality gates remain open.

The app changes through source commit `6977f5a` are pushed to private `ixcxyy/Sinnfaden`. The final candidate was rebuilt from clean checkout `75c9cad` (documentation only after that code commit) at `Artifacts/overnight-2026-10-20/Candidate-final/Sinnfaden.app` (0.4.3, build 7). Keep the existing design and free hosting configuration. If source changes again, rebuild, retest and prepare a new local archive before updating this handoff; never replace published bytes.

## What is ready

- **196 automated tests passed in the release verification:** 174 Swift (137 core + 37 app), 17 reporting-relay and 5 release-staging tests. Evidence: `Artifacts/overnight-final-swift-tests.log`, `overnight-final-relay-tests.log`, `overnight-final-release-tests.log`.
- Release compilation and deep/strict code-sign verification passed for the final candidate. Evidence: `Artifacts/overnight-final-build.log`.
- Native demo tests covered lesson feedback, oversized recipe drafts, number/date fields, multi-choice selections, oversized generated fields, correction and restart persistence. The checkpoint records the exact candidate tested for each case; this is not a claim that every native check used batch 23.
- The reporting relay's pagination/reconciliation fix is already live on the existing Free Worker. All 17 relay tests passed; a repeat of the known synthetic report was acknowledged. No new issue or paid resource was created.
- A final service check at **05:56 Vienna** again received HTTP 200 / `accepted: true` for the same known synthetic fingerprint. The public appcast's Sparkle signature passed verification and still lists **0.4.2/build 6**. Evidence: `Artifacts/overnight-final-relay-live.json`, `Artifacts/overnight-final-live-appcast.xml`.
- User-facing notes from [release-notes/0.4.3.md](release-notes/0.4.3.md) are included in the signed package. Local preparation succeeded using the existing Keychain key; no new key or credential was created.
- **Exact signed package:** `Artifacts/overnight-2026-10-20/Release-final/Sinnfaden-0.4.3-7.zip`, 3,684,474 bytes, SHA-256 `3f3c72a8786c2fd02900b605224f61904e3266584f6af854d577d4b798482ada`. Appcast, archive and notes passed Sparkle signature verification and the free hosting size limit, then staged only to `Artifacts/overnight-2026-10-20/Site-final`. Existing `Artifacts/updates` and `Artifacts/update-site` were preserved. Evidence: `Artifacts/overnight-final-package.log`, `overnight-final-verification.log`, `Artifacts/overnight-2026-10-20/release-final-verification.json`.
- Extracting that archive to `Artifacts/overnight-2026-10-20/ArchiveCheck-final` passed deep/strict code-sign verification; its executable exactly matches the built candidate (SHA-256 `4f895f4d052c99f1eca1cd7fcc40ccb7bc1fa89420c1d5e00709ed6aa5b005d2`). Extraction is **not** a completed update installation test.

## What prevents publication

1. **Installation has not completed.** The isolated build 6 → 7 test downloaded and verified an earlier six-batch archive but is stalled at file replacement. Installer PIDs 84440/84441 and the loopback server remain active. Its source, archive and target must not be overwritten or interrupted during that transaction. No specific permission cause has been confirmed. The production feed still offers 0.4.2/build 6.
2. **Live account quality is unverified.** The original app produced an empty-answer error; the old first candidate is blocked in macOS credential access. The later parser and asynchronous-read fixes have synthetic regression coverage, but no overnight candidate has completed a real connected-account prompt test. Preserve the account and pending user permission question; do not retrieve credentials elsewhere or substitute paid API usage.
3. **The exact final archive still needs its own installation test.** Success of the current six-batch test would not validate the final package. The final app, archive, feed and notes now pass their signature checks; replacement of an older installed app and subsequent startup remain unverified.

## Remaining release sequence

1. Preserve the completed verification and final package. From 06:00, prioritize installation status and documentation. Repeat builds/tests only if source changes or new evidence requires it.
2. Keep `Release-final` bytes unchanged. Preserve `Artifacts/updates` and every previously published archive; never replace published bytes under the same version/build.
3. Once the existing transaction finishes, test the exact final archive on a separate older app copy using an isolated signed test feed. Confirm installed version, deep/strict code signature, executable identity and startup with `--demo`. Preserve owner data and the connected account. Do not start overlapping installers for the same bundle or interrupt the active replacement.
4. Only after the required gates pass, add `0.4.3+7` to the relay allowlist, retaining supported older versions. Stage the verified signed files with the retained prior releases and deploy through the existing free Workers. Verify the public feed/download bytes and reporting acknowledgement after publication.
5. At 06:30 stop new edits, report the actual gates passed and any remaining blockers, and pause both overnight automations. If installation is still stalled, leave 0.4.2 live and report 0.4.3 as prepared but unpublished.

This remains free **development distribution**: ad hoc app signing plus Sparkle update signatures, with no Apple Developer ID or notarization. No hosting upgrade, new token, signing-key replacement or paid API fallback is needed for the prepared work. See [FREE-HOSTING.md](FREE-HOSTING.md) for existing service credentials and operations, and [OVERNIGHT-2026-10-20.md](OVERNIGHT-2026-10-20.md) for detailed evidence and process state.
