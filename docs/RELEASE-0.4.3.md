# Sinnfaden 0.4.3 release handoff

**Prepared 20 October 2026, 05:00 Europe/Vienna. Unpublished.**

The app changes through source commit `6977f5a` are pushed to private `ixcxyy/Sinnfaden`. The latest compiled candidate is `Artifacts/overnight-2026-10-20/Candidate-batch23/Sinnfaden.app` (0.4.3, build 7). Keep the existing design and free hosting configuration. If source changes again, rebuild and update this handoff before signing the final archive.

## What is ready

- **174 Swift tests passed:** 137 core and 37 application tests. Evidence: `Artifacts/overnight-terminal-content-after.log`.
- Release compilation and deep/strict code-sign verification passed for that candidate. Evidence: `Artifacts/overnight-build-batch23.log`.
- Native demo tests covered lesson feedback, oversized recipe drafts, number/date fields, multi-choice selections, oversized generated fields, correction and restart persistence. The checkpoint records the exact candidate tested for each case; this is not a claim that every native check used batch 23.
- The reporting relay's pagination/reconciliation fix is already live on the existing Free Worker. All 17 relay tests passed; a repeat of the known synthetic report was acknowledged. No new issue or paid resource was created.
- Proposed user-facing notes are in [release-notes/0.4.3.md](release-notes/0.4.3.md). They can be passed as `KLAR_RELEASE_NOTES` when preparing the final archive.

## What prevents publication

1. **Installation has not completed.** The isolated build 6 → 7 test downloaded and verified an earlier six-batch archive but is stalled at file replacement. Installer PIDs 84440/84441 and the loopback server remain active. Its source, archive and target must not be overwritten or interrupted during that transaction. No specific permission cause has been confirmed. The production feed still offers 0.4.2/build 6.
2. **Live account quality is unverified.** The original app produced an empty-answer error; the old first candidate is blocked in macOS credential access. The later parser and asynchronous-read fixes have synthetic regression coverage, but no overnight candidate has completed a real connected-account prompt test. Preserve the account and pending user permission question; do not retrieve credentials elsewhere or substitute paid API usage.
3. **The exact final archive still needs its own installation test.** Success of the current six-batch test would not validate batch 23 or a later candidate. Existing signature verification is app code-sign validation; the final archive and feed must also receive and pass Sparkle Ed25519 verification.

## Remaining release sequence

1. From 06:00, freeze new feature scope. Run the final Swift, relay and release-staging suites. Review the final source diff and build the selected candidate into a separate directory.
2. Prepare the signed development archive, release notes and feed in a fresh local release directory using the existing Keychain key. Preserve `Artifacts/updates` and every previously published archive; never replace published bytes under the same version/build.
3. Verify the signed feed, archive, notes, declared sizes and 25 MiB hosting limit. Test the exact archive on a separate older app copy using an isolated signed test feed. Confirm installed version, deep/strict code signature, executable identity and startup with `--demo`. Preserve owner data and the connected account.
4. Only after the required gates pass, add `0.4.3+7` to the relay allowlist, retaining supported older versions. Stage the verified signed files with the retained prior releases and deploy through the existing free Workers. Verify the public feed/download bytes and reporting acknowledgement after publication.
5. At 06:30 stop new edits, report the actual gates passed and any remaining blockers, and pause both overnight automations. If installation is still stalled, leave 0.4.2 live and report 0.4.3 as prepared but unpublished.

This remains free **development distribution**: ad hoc app signing plus Sparkle update signatures, with no Apple Developer ID or notarization. No hosting upgrade, new token, signing-key replacement or paid API fallback is needed for the prepared work. See [FREE-HOSTING.md](FREE-HOSTING.md) for existing service credentials and operations, and [OVERNIGHT-2026-10-20.md](OVERNIGHT-2026-10-20.md) for detailed evidence and process state.
