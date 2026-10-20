# Sinnfaden 0.4.5 / build 10 — accurate lesson feedback

Installed and published on **20 October 2026, approximately 20:25 Vienna**. Source fix: `7ef9b36`. The [quality report](PROMPT-QUALITY-2026-10-20.md) records the live prompt scenarios, reproduced grading defects and regression evidence.

## Verification

- **204 tests passed:** 182 Swift, 17 relay, 5 release-staging.
- Native checks rejected both the incorrect `16:30` time change and the reversed Tuesday-to-Wednesday correction. A correct Wednesday-to-Tuesday correction preserving `16.00 Uhr` received positive feedback.
- The exact signed archive updated a separate build-9 copy to build 10 through Sparkle. macOS briefly waited in `renamex_np`, then completed. The installed test copy passed deep/strict signature verification, matched the candidate executable, reached its main screen and quit normally. The local feed server was then stopped.
- `/Applications/Sinnfaden.app` was replaced using the same verified archive. It is **0.4.5/build 10** and passes deep/strict signature verification. Build 9 is retained at `Artifacts/prompt-quality/PreviousInstalled/Sinnfaden.app`; account storage was not replaced.
- The Applications copy restored its existing ChatGPT connection. Reopening the answer-checking lesson refreshed the two saved incorrect attempts: the lesson is “Begonnen”, not completed, and the latest answer now correctly shows “Noch nicht ganz”. Drafts and both attempts remain intact.
- The app's **Nach Updates suchen …** confirms that **0.4.5 is the newest version**. The app is left open on the prompt screen.

## Publication

- Signed archive: `Sinnfaden-0.4.5-10.zip`, **3,686,437 bytes**.
- SHA-256: `71fdf154024fd04a2f4fecbf25352ceab25800a315d52eb3086dcb831b058c53`.
- Static update deployment: `e24c3ca4-b38e-4d59-9da6-5be937ae26d2`.
- Report relay deployment: `6e832885-6d85-469f-ba46-04b73b49b4cd`; supported release allowlist includes `0.4.5+10`.
- The public feed contains **10, 9, 8 and 6**. All **eight** referenced files/feed were downloaded over verified HTTPS and matched local sizes and SHA-256 hashes. Their Ed25519 signatures passed. Immutable archive bytes are retained in `Artifacts/updates`.

Publication verification caught an operational error: generating a fresh appcast with only `--versions 10` omitted historical entries even though their archives were copied. The first deployment consequently returned 404 for an older download. The feed was regenerated starting from the previous signed appcast, re-staged and redeployed; all retained downloads now verify. Future releases using a fresh output folder must carry forward the existing signed feed and assert the expected retained version list before deployment.

Artifacts and exact verification flags are in `Artifacts/prompt-quality/verification.json`; deployment, installation, native feedback and update-check evidence are in the same directory.

## Limits

The grading is intentionally local and specific to the fixed exercise; it is not unrestricted semantic grading. The live prompt quality sample cannot guarantee every future model response. Design and tutor instructions remain unchanged. Development code signing and Sparkle update signatures are configured; Apple Developer ID/notarization remain unconfigured. Hosting remains on the existing Free services. No paid API key, hosting resource or signing membership was added.
