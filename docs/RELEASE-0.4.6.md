# Sinnfaden 0.4.6 / build 11 – release verification

Published and installed on **20 October 2026, approximately 22:07 Vienna**. Release type: **regular**, development distribution (`--development`).

## Source

- Release source commit: `d4532a663373a96c591a68c3b5a2a7d4753eea72` on `main` (also pushed as `release/0.4.6`). It contains the interaction commit `c21f4b6` (hover explanation, send transition, loading body) and the version preparation `d4532a6` (version 0.4.6/11, relay allowlist `0.4.6+11`, [release notes](release-notes/0.4.6.md)).
- The package was built from exactly this source state; integration into `main` was a fast-forward and changed no code.

## Automated checks (run for this release)

- `swift test`: **182 tests passed**, 0 failed.
- `npm --prefix services/bug-relay ci`, `test` (**17 passed**) and `run check`: passed.
- `python3 -m unittest discover -s Tests/ReleaseTests -v`: **5 passed**.
- `git diff --check` and `git diff --cached --check`: clean.
- `scripts/check-annotations.sh`: **70 native annotation checks** passed.
- Bubble lab autoplay (normal and with forced reduced motion and reduced transparency): all states including arming → forming → following → morphing → reading → pinned → retracting, and reversal during retraction, completed without errors; measured ~0.16 s from hover to formation and ~120 rendered lens frames/s.

## Native interaction checks (demo mode, no account data)

- Hover explanation with the app's scripted pointer: forms beside the pointer below the hovered line, follows along the phrase, morphs between explanations and closes on leave. Milky material, blue heading, readable ink text.
- Send transition with real text input and ⌘↵ (`--compose-probe`): first frame matches the editor words without a duplicate layer; words gather along curved paths, merge into the body; status and cancel visible from the start; result appears after the demo stages.
- "Already clear" outcome (`--demo-good`) and improved outcome: prompt text sits in its slot, controls clickable.
- A recording is in `Artifacts/Sinnfaden-Hover-Senden-Laden.mp4`.

Not verified by Claude: hover with the physical mouse (stopped because Jonas was using the computer), dark appearance (the app is fixed to light), window resizing during hover, and new live-account prompt samples with build 11. Prompt generation, teaching feedback and storage code are unchanged in this release.

## Package

| | |
|---|---|
| Archive | `Sinnfaden-0.4.6-11.zip` |
| Public URL | `https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/Sinnfaden-0.4.6-11.zip` |
| Bytes | 3 695 245 |
| SHA-256 | `dc4151f57d48f3aad16b27c2c15f7a9e825204f01ee8eaa5a4fc61268b32cff6` |
| Architecture | arm64 only (no universal build claimed) |
| Signing | ad hoc code signature plus Sparkle Ed25519 (`at.klar.promptcoach`); **not Apple-notarized** |

Delta updates from builds 10, 9, 8 and 6 are published beside it.

## Isolated Sparkle installation test

- Starting point: a separate copy of the published build-10 archive (SHA-256 `71fdf154…`, identical to the live file) under `Artifacts/release-0.4.6-11/update-test/InstallTarget/`.
- Feed: separate signed test feed with loopback URLs (`127.0.0.1:8771`, archive and release notes), containing the unchanged candidate ZIP. Production feed and configuration were not touched.
- Result: Sparkle found the signed update 11, verified and installed it (22:03:28) and relaunched (22:03:29). The test copy reports 0.4.6/11, passes `codesign --verify --deep --strict`, and its executable is byte-identical to the candidate archive's. A demo start of the test copy succeeded and was closed normally. The loopback server was stopped.

## Deployment

- Relay (`services/bug-relay`): version `0061501a-a532-48a6-95d5-1c66cfbc6b3f`, deployed 2026-10-20T20:05:24Z (start), allowlist now includes `0.4.6+11`.
- Update host (`services/update-host`): version `32468442-d792-4e7a-b886-74f4bd221300`, deployed 2026-10-20T20:05:41Z (start); 7 new files uploaded, 7 unchanged.
- Both dry runs passed before deployment. Hosting remains on the Free plan; no paid resource was added.

## Public verification (after deployment)

- The live `appcast.xml` was downloaded over verified HTTPS and passed `sign_update --verify`. It lists builds **11, 10, 9, 8 and 6**.
- All 13 referenced files (5 archives, 4 deltas, 4 release notes) returned HTTP 200, matched the declared length and the local SHA-256, and passed their individual Ed25519 signature checks. The older archives keep their previous hashes and URLs.

## Installed app

- `/Applications/Sinnfaden.app` was backed up first (`Artifacts/release-0.4.6-11/applications-backup/`, build 10, signature valid).
- Jonas installed the live update through **„Nach Updates suchen …“** in the running app. Afterwards the bundle reports **0.4.6 / 11**, passes deep/strict code-sign verification, its executable is byte-identical to the published archive's, and it is running from `/Applications/Sinnfaden.app` (started 22:07:28).
- No errors from the app's log subsystem since the restart. The connection registration and the active account's store were reopened at 22:07; account data is intact (21 history entries in the active account, other account stores unchanged). Contents were not read.
- Not verified by Claude: a manual „Nach Updates suchen …“ after the restart reporting 0.4.6 as current, and a new live prompt with the existing connection.

Evidence (local, not in Git): `Artifacts/release-0.4.6-11/` – live feed before and after, hashes, test logs, build and staging logs, deployment logs, update-test files and the handoff note.
