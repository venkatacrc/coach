#!/usr/bin/env bash
# Rebuilds content.json from content/ and seals it with your passcode, so the public repo and
# site only hold content.vault and web/content.enc. Commit and push afterwards to publish.
# Usage: scripts/publish_web.sh      (passcode from $COACH_PASSCODE or .passcode)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$ROOT/content" ]; then
    node "$ROOT/tools/lock.mjs" open
fi
python3 "$ROOT/tools/build_content.py"
node "$ROOT/tools/lock.mjs" seal
echo "Now commit content.vault and web/content.enc, and push to publish."
