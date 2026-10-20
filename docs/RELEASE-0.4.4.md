# Sinnfaden 0.4.4 / build 9 — prompt visibility fix

**Installed, live-tested and published on 20 October 2026 at 19:58 Vienna.** The Applications copy is running with the existing ChatGPT account. The public feed serves build 9, retaining builds 8 and 6.

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
- Exact signed package and combined feed: `Artifacts/prompt-fix-build9/Release` and `Publish`; old published builds 6 and 8 are retained unchanged. All six referenced files passed staging/signature checks. Exact hashes are in `Artifacts/prompt-fix-build9/verification.json`. The same files were deployed and downloaded again over HTTPS; every size, SHA-256 hash and Ed25519 signature passed verification.
- The reporting Worker accepts build 9 alongside supported prior releases. Deployment `71b625dd-588c-41bc-bab7-62fb084d8bfb`. No new issue was created for this check.
- **Live installed-app test passed:** `/Applications/Sinnfaden.app` restored the existing saved ChatGPT account, generated a response to the generic appointment-email prompt, and immediately displayed the improved prompt, three generated input fields, copy/edit controls and collapsed optional practice. The incoming-response progress message also appeared. Evidence: `Artifacts/prompt-fix-build9/installed-live-result.txt` and `.png`.
- The running app's **Nach Updates suchen …** displayed “Sinnfaden 0.4.4 is currently the newest version available.” Evidence: `Artifacts/prompt-fix-build9/installed-update-check.txt` and `.png`.

## Completed installation and publication

The two operations that were waiting in macOS file replacement at 18:57 completed before the 19:53 inspection. Their installer processes exited. The Applications installation command returned exit code 0. The observations established a delay in `rename` / `renamex_np`, but not its underlying macOS cause; no security setting was disabled.

1. **Separate Sparkle copy:** the exact signed build-9 archive replaced build 8 in `Artifacts/prompt-fix-build9/InstallTarget/Sinnfaden.app`. Deep/strict code-sign verification passed, and its executable matches the release candidate. It was started explicitly in demo mode, reached the main screen and quit normally with exit code 0. The local test server was stopped after completion.
2. **Applications copy:** `/Applications/Sinnfaden.app` is **0.4.4/build 9**, installed from the same signed archive. Deep/strict verification and executable identity checks passed. The old build 8 is retained at `Artifacts/prompt-fix-build9/PreviousInstalled/Sinnfaden.app`. Account/history storage was not replaced. Saved-login restoration completed, followed by the successful live prompt test above. The app is left open for the user.
3. **Public update:** deployment `29f85247-ed52-4f28-ad0a-49aa3333c508` serves the verified files through the existing free static Worker. The public feed lists builds **9, 8 and 6**. All six downloaded files match the verified candidate hashes and signatures. Exact published bytes are retained in `Artifacts/updates`; older archives were not changed.

Published build-9 archive: **3,685,250 bytes**, SHA-256 `9df8e58bcaf3896a2bbb38635b8262e9f9a447c5796803031b27d71f186344b0`.

## Remaining limitations

The development app remains ad hoc signed and not Apple-notarized; Sparkle authenticates the update with the existing Ed25519 key. Future rebuilt apps can still require macOS Keychain approval, and the cause of the earlier file-replacement delay has not been established. No paid hosting, signing membership or API service was added. Both overnight automations remain paused.
