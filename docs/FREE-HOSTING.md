# Free hosting and release operations

Configured on 19 October 2026 for Sinnfaden 0.4.2 (build 6). Cloudflare's dashboard was checked: **Free, $0, Current plan**. No paid plan, domain, R2 bucket, or paid build runner was provisioned.

## Services

- Reports: `https://sinnfaden-bug-relay.sinnfaden-bug-relay.workers.dev/v1/reports`
- Signed update feed: `https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/appcast.xml`
- Update archive: `https://sinnfaden-updates.sinnfaden-bug-relay.workers.dev/Sinnfaden-0.4.2-6.zip`
- Private source and issues: <https://github.com/ixcxyy/Sinnfaden>

The two Workers deploy independently so a reporting change does not remove hosted update files. The update Worker serves static assets directly, without executing application code for each download. The relay uses SQLite-backed Durable Objects, supported on the Free plan. A free `workers.dev` address provides HTTPS without buying a domain.

Keep the account on **Workers Free**. Free-limit exhaustion causes failures rather than paid overages. The app retains reports for retry. Static asset requests/storage are free, with a maximum of **25 MiB per file**. Release staging refuses larger files; it never upgrades the account or falls back to a paid product. These are the provider's current limits, not a promise that its terms will never change.

Update archives and the feed are publicly downloadable. They contain the compiled app and public configuration, not source history, diagnostic records, or credentials. The source repository and reports stay private. Builds/signing run locally on this Mac, avoiding paid hosted build minutes.

## Owner credentials

Cloudflare access was connected through Wrangler's browser login with Keychain storage enabled. A future Mac can use `scripts/connect-cloudflare.command` after `npm ci` in `services/bug-relay`.

The relay needs a **fine-grained GitHub token**, restricted to **ixcxyy/Sinnfaden only**, with **Issues: read/write** and the default Metadata read permission. It needs no source-code write access. Create it in GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens. The setup link suggests a 90-day lifetime; check the actual expiry on GitHub and replace it before expiry. Use `scripts/connect-github-reports.command` to enter the token into Wrangler's private prompt and store it as the Worker's encrypted `GITHUB_TOKEN` secret. Do not paste it into chat, put it into a shell command, or commit it. Running the script again rotates the token.

Reports appear in the private repository's Issues list. GitHub may suppress notifications for actions made by your own token; Watch alone does not guarantee email/push alerts for those reports. A separate GitHub App/bot identity is needed if guaranteed separate-actor GitHub notifications become a requirement. The app itself requires reporting consent in Settings → Updates & Fehler.

## Free signing and its limitation

A project-specific Ed25519 signing key was generated in this Mac's login Keychain under account **at.klar.promptcoach**. Its public key is checked into `Config/Info.plist`. Private key material was not exported, uploaded, or committed. Back up the login Keychain securely: losing this key without a Developer ID recovery path requires a manual app reinstall.

The archive, update feed and linked release notes must pass Sparkle signature verification before staging. Publishing checks that the key in the app matches the Keychain key. Updates still require the user's approval to download and install.

This is **development distribution**: the app is ad hoc code-signed and is not Apple-notarized. Sparkle's Ed25519 signatures authenticate updates; they do not give the first download Apple Developer ID trust. The first installation on another Mac may require macOS's explicit Open Anyway approval, or may be blocked by that Mac's policy. Do not disable Gatekeeper. Older builds with no configured updater need one manual installation of this configured build.

Apple's normal Developer ID/notarization route requires a paid Apple Developer Program membership (currently US$99/year, local pricing varies). None was purchased. The default production release command still requires Developer ID and notarization; `--development` explicitly selects this free route.

## Publish a later release

1. Increase `CFBundleVersion` and the visible version in `Config/Info.plist`. Add the new `version+build` to `ALLOWED_RELEASES` in the relay configuration, retaining supported versions.
2. Test the changes and build locally:

   ```sh
   swift test
   npm --prefix services/bug-relay test
   python3 -m unittest discover -s Tests/ReleaseTests -v
   ./scripts/build-app.sh
   ./scripts/prepare-update.sh regular --development
   python3 scripts/stage-updates.py
   ```

   Use `major` for a large feature patch or `critical` for an urgent fix. Never reuse a version/build or replace an already published archive with different bytes.

3. Publish the reviewed relay configuration and signed update files:

   ```sh
   WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --config services/bug-relay/wrangler.jsonc
   WRANGLER_SEND_METRICS=false services/bug-relay/node_modules/.bin/wrangler deploy --config services/update-host/wrangler.jsonc
   ```

   Static deployment uploads all assets before switching the active version. The staging directory contains only files referenced by the signed feed, plus cache headers. Keep `Artifacts/updates` as the local release archive; do not deploy the whole project or `Artifacts` directory. Rebuilding a feed without retained older releases can remove their downloads.

4. Verify the HTTPS feed signature, perform an update on a separate installed copy, and check that a synthetic report reaches the private issue inbox. Do not treat a successful upload as proof of an installed update.

## Deployment validation

- Both Workers deployed successfully on the Free plan.
- The live HTTPS feed and archive were downloaded; both Ed25519 signatures and the archive's declared length passed verification.
- Sparkle displayed the live 0.4.2 update to a separate 0.4.1 test copy, downloaded and verified it, replaced build 5 with build 6, and relaunched the updated app. The installed copy passed deep/strict code-sign verification. macOS delayed the file replacement for several minutes before completing; no security protection was disabled. The relaunched test copy was then closed.
- Five release-staging tests and thirteen relay tests pass. The local release app passed deep/strict code-sign verification; its development DMG checksum is valid.
- The owner saved the scoped GitHub token in Cloudflare. A synthetic live report returned HTTP 201 and created [private issue #1](https://github.com/ixcxyy/Sinnfaden/issues/1). A second report with the same fingerprint returned HTTP 200, with one issue verified through GitHub's authenticated API. The production Swift delivery client also received the live acknowledgement. The issue was marked as a setup test and closed.
- Live activation exposed a Cloudflare compatibility bug: `redirect: 'error'` throws before sending a request. The relay now uses `manual`, rejects non-success responses, and never follows a redirect with the GitHub token. Regression tests cover redirect rejection, token whitespace handling, and allowlisted operational logs. Logs contain only fixed failure stages/kinds and a numeric upstream status, never report contents or exception text; persistent observability remains disabled.
- Automatic bug reporting is enabled in the owner's running 0.4.2 app. Automatic update checks are enabled too. Earlier local reports stay local; only newly collected reports are queued after consent.

Sources checked 19 October 2026: [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Workers request redirect behavior](https://developers.cloudflare.com/workers/runtime-apis/request/), [static asset billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/), [static asset limits](https://developers.cloudflare.com/workers/platform/limits/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [Sparkle signing and distribution](https://sparkle-project.org/documentation/), [Apple membership](https://developer.apple.com/programs/), [GitHub token setup](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
