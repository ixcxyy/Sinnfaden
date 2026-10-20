# Sinnfaden 0.4.4 / build 9 — prompt visibility fix

## Reproduction and fix

The installed build 8 successfully generated a response to the saved generic appointment-email prompt, but hid the finished prompt and its input fields behind an automatically opened “Selbst ausprobieren” exercise. The user had to find “Vorschlag ansehen” before the requested result appeared. The demo already showed results immediately, which concealed this live/demo difference in earlier native checks.

Build 9 uses the same result-presentation function for live requests and the demo. A completed improved prompt appears immediately, with its generated fields and copy/edit controls. Practice remains available underneath and starts collapsed. Seeing the worked example marks subsequent practice as supported; it does not falsely count as an independent attempt. A real clarification still shows a question rather than pretending to have generated a prompt. Initial response text now changes the progress message without exposing unvalidated partial output; cancellation, account and current-attempt guards remain.

No visual styling, provider credentials, model selection or response-validation rules changed.

## Evidence

- Source fix pushed to `main`: `9e0d9eb`.
- Three regression tests failed against the previous live-result behavior (six failed assertions), then passed after the fix. They cover an improved prompt with an exercise, an already-clear prompt with optional practice, and a real clarification.
- **201 automated tests passed:** 179 Swift, 17 relay, 5 release-staging. Evidence: `Artifacts/prompt-visibility-before.log`, `prompt-visibility-after.log`, `prompt-fix-relay-tests.log`, `prompt-fix-release-tests.log`.
- Manual diff review, release compilation, deep/strict signing checks and the local AST graph update passed.
- Native build-9 demo check: the full result and controls appeared immediately without pressing reveal or completing practice. Selecting the time option and filling the name updated the prompt and completed its fields. Evidence: `Artifacts/prompt-fix-build9/native-visible-result.txt` and `.png`. This is a local UI check, not a real build-9 inference claim.
- Exact signed package and combined feed: `Artifacts/prompt-fix-build9/Release` and `Publish`; old published builds 6 and 8 are retained unchanged. All six referenced files passed staging/signature checks. Exact hashes are in `Artifacts/prompt-fix-build9/verification.json`. `Artifacts/update-site` contains the verified candidate files; they have **not** been deployed.
- The reporting Worker accepts build 9 alongside supported prior releases. Deployment `71b625dd-588c-41bc-bab7-62fb084d8bfb`. No new issue was created for this check.

## Installation status at 18:57 Vienna, 20 October

The rebuilt app's saved-login read was waiting in Keychain; its settings were closed and it was quit normally. No new login, credential extraction or permission bypass was attempted. Build 9 has not yet completed a real connected-account generation.

Two independent installation operations are pending inside macOS file rename:

1. **Separate Sparkle copy:** `Artifacts/prompt-fix-build9/InstallTarget/Sinnfaden.app` is still build 8. The exact signed build-9 archive was downloaded, verified, extracted and installation confirmed through the helper. Installer PIDs 62333/62334 remain active; a process sample shows the installer in `renamex_np`. Local test server PID 62289 serves port 8770. Do not relaunch the closed `UpdateCheck.app` or interrupt the replacement.
2. **Applications copy:** `/Applications/Sinnfaden.app` is still build 8. The replacement command has verified and extracted the build-9 archive but is waiting to move the old app to `Artifacts/prompt-fix-build9/PreviousInstalled/Sinnfaden.app`. Python PID 62759 / execution session 76536 is in `rename`; the backup does not yet exist. The script installs the verified new bundle after preserving the old one and restores the old path if the second rename fails. Do not kill this operation or start another replacement of the same app.

These observations establish where the operations are waiting, not which macOS permission or service is responsible. No current prompt requesting approval was confirmed. The public update feed remains **0.4.3/build 8**. Publication of build 9 is held until the separate installation gate finishes. Both overnight automations remain paused.

## Finish after macOS releases the operations

Inspect actual processes and both bundle versions first. Once the separate target is build 9, verify its deep/strict signature and executable identity against `Candidate/Sinnfaden.app`; start it explicitly in demo mode and quit normally. Stop the local server only after its transaction is complete. Confirm the Applications copy is build 9, then open that exact path, preserve the saved account and verify the visible live result when access is available.

Only then publish the already verified `Artifacts/update-site` using the existing free update Worker. Verify the public feed and every referenced download against the candidate hashes, preserve immutable archive bytes in `Artifacts/updates`, and record deployment and installation evidence here. Never replace the published build-8 archive or claim a pending rename is a completed installation.
