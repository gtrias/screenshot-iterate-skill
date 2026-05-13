#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q

SESSION=$("$REPO/scripts/screenshot.sh" session-init "homepage")
"$REPO/scripts/screenshot.sh" session-finalize --session "$SESSION" --score-initial 62 --score-final 81

[ -f .screenshot-iterate/INDEX.md ] || { echo "FAIL: INDEX.md missing"; exit 1; }
grep -q "^# Screenshot-Iterate Session Log" .screenshot-iterate/INDEX.md \
  || { echo "FAIL: INDEX.md header missing"; exit 1; }
grep -q "homepage" .screenshot-iterate/INDEX.md || { echo "FAIL: target missing"; exit 1; }
grep -q "62" .screenshot-iterate/INDEX.md || { echo "FAIL: initial score missing"; exit 1; }
grep -q "81" .screenshot-iterate/INDEX.md || { echo "FAIL: final score missing"; exit 1; }

jq -e '.scores.initial == 62 and .scores.final == 81' "$SESSION/meta.json" >/dev/null \
  || { echo "FAIL: meta.json scores not updated"; exit 1; }

# Second finalize → INDEX.md gets a second line (header not duplicated)
SESSION2=$("$REPO/scripts/screenshot.sh" session-init "pricing")
"$REPO/scripts/screenshot.sh" session-finalize --session "$SESSION2" --score-initial 70 --score-final 90
[ "$(grep -c "^# Screenshot-Iterate Session Log" .screenshot-iterate/INDEX.md)" -eq 1 ] \
  || { echo "FAIL: header duplicated"; exit 1; }
grep -q "pricing" .screenshot-iterate/INDEX.md || { echo "FAIL: second session not appended"; exit 1; }

echo "PASS"
