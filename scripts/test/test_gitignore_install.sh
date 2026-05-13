#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q
"$REPO/scripts/screenshot.sh" session-init "homepage" > /dev/null
grep -q "^\.screenshot-iterate/" .gitignore || { echo "FAIL: .gitignore not updated"; exit 1; }
# Idempotency
"$REPO/scripts/screenshot.sh" session-init "another" > /dev/null
[ "$(grep -c '^\.screenshot-iterate/' .gitignore)" -eq 1 ] || { echo "FAIL: duplicated entry"; exit 1; }
# Pre-existing .gitignore content preserved
cd "$TMP"; rm -rf .screenshot-iterate .gitignore
echo "node_modules/" > .gitignore
"$REPO/scripts/screenshot.sh" session-init "third" > /dev/null
grep -q "^node_modules/" .gitignore || { echo "FAIL: pre-existing entry lost"; exit 1; }
grep -q "^\.screenshot-iterate/" .gitignore || { echo "FAIL: new entry missing"; exit 1; }
echo "PASS"
