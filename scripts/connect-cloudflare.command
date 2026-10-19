#!/bin/bash
# Run by the owner in Terminal; no password or token is printed or sent to chat.
set -euo pipefail
cd "$(dirname "$0")/../services/bug-relay"
export WRANGLER_SEND_METRICS=false
printf 'Connect your free Cloudflare account in the browser. This does not purchase a plan.\n'
./node_modules/.bin/wrangler login --use-keyring
printf '\nCloudflare is connected. Return to Codex and say the account is connected.\n'
read -r -p 'Press Return to close this window. ' _
