# Bug reports and app updates

Implemented on 19 October 2026. Current package: **Sinnfaden 0.4.1, build 5**.

## What works locally

- Settings → **Updates & Fehler** shows technical reports, their occurrence counts and delivery state. Reports can be exported or deleted locally.
- Automatic reporting is off by default. It becomes available when the app is built with a valid reporting URL. Enabling it queues new reports only; it does not upload earlier local reports. Disabling it cancels pending delivery and removes pending delivery flags. A request already accepted remotely cannot be recalled.
- Only component, fixed error category, HTTP status, release/build and a random report ID are sent. No prompt, response, raw exception message, account identifier, OAuth token, API key, file path or IP address is put in the payload. The relay necessarily sees the connection's IP for rate limiting; it does not include it in issues.
- Local history is bounded to 100 groups and 30 days, with one remote report per category/build/day. Delivery survives restart, requires an explicit acknowledgement and backs off on failure. User cancellation and normal usage limits are not bug reports.
- This captures handled errors in connection, coach, comparison, follow-up and storage operations. It is not a native crash-dump service, and it does not promise to detect every defect. Reports intentionally lack personal reproduction data.
- **Nach Updates suchen …** is in the app menu and settings. Sparkle 2.10 performs signed update verification and installation. Automatic checks are configurable; automatic downloads/installations are disabled. Major/critical releases can be marked in the release feed.
- A build without a feed/public key clearly reports that updates are not configured. It never falsely claims that it is up to date.

## Chosen flow

```mermaid
flowchart LR
    A[Sinnfaden catches a technical error] --> B[Local report and optional delivery queue]
    B --> C[HTTPS relay]
    C --> D[Private GitHub issue, grouped by defect and release]
    D --> E[Jonas reviews; reproduce, test and fix]
    E --> F[Sign and notarize new app]
    F --> G[Publish signed update feed]
    G --> H[Check for updates or automatic notification]
    H --> I[User approves download and installation]
```

The connected ChatGPT account can be used to help understand an exported technical report. The existing Sign in with ChatGPT route supports model inference, not a documented way to send a message to the developer's ChatGPT inbox. No chat posting, account-token forwarding, unattended code fixing, or automatic release publishing is implemented.

## Activate private GitHub delivery

The report destination is **[ixcxyy/Sinnfaden](https://github.com/ixcxyy/Sinnfaden)**. Its private visibility and enabled Issues were verified through GitHub's authenticated API on 19 October 2026. No diagnostic report has been sent remotely; the relay is not deployed yet.

1. The private repository and Issues are ready. Keep this repository private: the relay refuses to create reports in a public repository.
2. Create a fine-grained GitHub token restricted to that repository with Issues read/write and the default Metadata read access. Keep it only as the relay's `GITHUB_TOKEN` secret. It must never appear in the Mac app or source control. GitHub App installation tokens can replace it later.
3. `services/bug-relay/wrangler.jsonc` already sets `GITHUB_REPOSITORY` to `ixcxyy/Sinnfaden`. `ALLOWED_RELEASES` is a comma-separated allowlist of `version+build`, initially `0.4.1+5`. Keep supported older releases while updating it. This reduces forged-report abuse; the public endpoint is not proof that a real installation generated a report.
4. In that directory, run `npm ci`, `npm test`, and `npx wrangler deploy --dry-run`. Connect the intended Cloudflare account, set the secret using `npx wrangler secret put GITHUB_TOKEN`, and deploy with `npx wrangler deploy` when ready. Deployment/account setup is deliberately not done here.
5. Set `KLAR_BUG_REPORT_URL=https://YOUR-WORKER.workers.dev/v1/reports` when building the app. Enable reporting in Settings → Updates & Fehler on each consenting installation.
6. Watch the private repository's Issues notifications in GitHub; email or mobile alerts are controlled by your GitHub account settings. These preferences were not changed here.

The relay validates a strict payload, applies 10 requests/minute per edge IP, checks that the repository is private, and caps new issues at 20/day across the repository. A Durable Object serializes duplicate submissions. No GitHub token is returned to the app. Reports are unverified input: no issue automatically executes commands or triggers a release.

If GitHub times out after an issue POST, the relay persists that uncertainty and looks for the report marker before trying anything else. If reconciliation cannot find the issue, it returns a retryable failure rather than blindly creating a duplicate. Inspect the repository and the corresponding Durable Object key before clearing an unresolved `creating` marker; otherwise leave it for investigation. Definite GitHub 4xx rejections can retry after permissions/rate limits are corrected. Repeated reports for an existing group do not create comments or reopen closed issues; a new app build forms a new group.

This service uses Cloudflare Workers/Durable Objects. Hosting accounts, quotas and any charges are the owner's responsibility; no paid resource was provisioned.

## Activate secure updates

1. Set up a persistent HTTPS location for `appcast.xml` and release archives. Static object hosting is enough; the GitHub bug repository can remain private. Do not embed a private GitHub download token in the app.
2. Generate a **project-specific** Sparkle signing key with `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. Back up the private key securely; embed only the displayed public key. The tool uses the macOS Keychain. No signing key was created during this task.
3. Supply both `KLAR_UPDATE_FEED_URL=https://YOUR-HOST/updates/appcast.xml` and `KLAR_UPDATE_PUBLIC_KEY=YOUR-PUBLIC-KEY` to the build. Optionally set `KLAR_VERSION` and `KLAR_BUILD_NUMBER`; the checked-in defaults are in `Config/Info.plist`. Always increase the build number.
4. Use a Developer ID identity and notary profile with the existing `scripts/notarize.sh`. The packaging script embeds Sparkle, signs its helpers inside out, preserves helper entitlements, and removes build-machine framework search paths.
5. Run `scripts/prepare-update.sh regular`, `major`, or `critical`. Optional `KLAR_RELEASE_NOTES` points to a Markdown file. This validates the signed/notarized bundle, prepares an archive, generates signed appcast/release notes and delta updates, and verifies the feed signature. It never uploads. The URL must end in `/appcast.xml` and archives are published beside it.
6. Review and upload archives/notes/deltas first, then `appcast.xml` last. Do not modify a signed feed after generation. Test a real older installed release upgrading to the new one before a broad rollout.

Major releases use Sparkle's minimum-autoupdate version marker. Critical releases use its critical-update marker. Automatic checks default to enabled for a configured release, and users can turn them off. Downloads require confirmation for every update. The app can only update while it is running and can reach the feed; it is not a system-wide push service.

The current development app is ad hoc signed. Developer ID, notarization, hosted feed, signing key and real old-to-new installation remain **unconfigured/unverified**. Existing 0.3/0.4 builds without Sparkle need one manual installation of this first updater-enabled release.

## Verification

- `swift test`: 89 tests pass, including new backend regression and diagnostics tests.
- `npm test` in `services/bug-relay`: 10 tests pass (validation, privacy, duplicate concurrency, private-only issues, rate limiting, definite failures and uncertain POST recovery).
- `npx wrangler deploy --dry-run`: validates/bundles the relay and all bindings without deploying.
- Local Wrangler runtime returns `503 {"accepted":false}` when unconfigured.
- Release app build and embedded framework code-sign verification pass. Full live GitHub delivery and real signed update installation require the activation steps above.

Official references: [OpenAI sign-in limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations), [Sparkle setup](https://sparkle-project.org/documentation/), [Sparkle release publishing](https://sparkle-project.org/documentation/publishing/), [GitHub issue API](https://docs.github.com/en/rest/issues/issues#create-an-issue), [Cloudflare rate limits](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [Durable Object storage](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/).
