#!/bin/bash
# The token is entered in Wrangler's private prompt, never an argument or source file.
set -euo pipefail
cd "$(dirname "$0")/../services/bug-relay"
export WRANGLER_SEND_METRICS=false
printf 'Use a fine-grained GitHub token for ixcxyy/Sinnfaden only, with Issues read/write.\n'
printf 'Paste it into the private prompt below. Do not paste it into Codex chat.\n\n'
./node_modules/.bin/wrangler secret put GITHUB_TOKEN
printf '\nThe reporting token is saved in Cloudflare. Return to Codex to verify delivery.\n'
read -r -p 'Press Return to close this window. ' _
