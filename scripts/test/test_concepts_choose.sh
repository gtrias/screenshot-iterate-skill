#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q
SESSION=$("$REPO/scripts/screenshot.sh" session-init "x")
printf '\x89PNG\r\n\x1a\n' > "$SESSION/baseline.png"

MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 p1 --label-1 Bold \
  --prompt-2 p2 --label-2 Minimal \
  --prompt-3 p3 --label-3 Editorial

"$REPO/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 1 --option 2

[ -f "$SESSION/concepts/chosen.png" ] || { echo "FAIL: chosen.png not written"; exit 1; }
jq -e '.chosen.round == 1 and .chosen.option == 2 and .chosen.label == "Minimal"' \
  "$SESSION/meta.json" > /dev/null || { echo "FAIL: meta.json not updated"; exit 1; }

# Failure modes
if "$REPO/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 99 --option 1 2>/dev/null; then
  echo "FAIL: should reject missing round"; exit 1
fi
if "$REPO/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 1 --option 9 2>/dev/null; then
  echo "FAIL: should reject out-of-range option"; exit 1
fi

echo "PASS"
