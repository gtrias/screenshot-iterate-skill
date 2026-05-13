#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q

# Pretend Storybook is present
mkdir -p .storybook && echo "module.exports = {};" > .storybook/main.js

SESSION=$("$REPO/scripts/screenshot.sh" session-init "checkout")
printf '\x89PNG\r\n\x1a\n' > "$SESSION/baseline.png"

MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 "p1" --label-1 Bold \
  --prompt-2 "p2" --label-2 Minimal \
  --prompt-3 "p3" --label-3 Editorial

"$REPO/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 1 --option 3

"$REPO/scripts/screenshot.sh" session-finalize \
  --session "$SESSION" --score-initial 60 --score-final 85

# Assertions
jq -e '.target == "checkout"' "$SESSION/meta.json" >/dev/null
jq -e '.chosen.label == "Editorial"' "$SESSION/meta.json" >/dev/null
jq -e '.chosen.round == 1' "$SESSION/meta.json" >/dev/null
jq -e '.chosen.option == 3' "$SESSION/meta.json" >/dev/null
jq -e '.scores.initial == 60 and .scores.final == 85' "$SESSION/meta.json" >/dev/null
[ -f "$SESSION/concepts/chosen.png" ] || { echo "FAIL: chosen.png missing"; exit 1; }
[ -f "$SESSION/concepts/round-1/option-1.png" ]
[ -f "$SESSION/concepts/round-1/option-2.png" ]
[ -f "$SESSION/concepts/round-1/option-3.png" ]
[ -f src/stories/ScreenshotIterateConcepts.stories.tsx ] || { echo "FAIL: story missing"; exit 1; }
grep -q "Editorial" src/stories/ScreenshotIterateConcepts.stories.tsx
grep -q "^\.screenshot-iterate/" .gitignore || { echo "FAIL: dir not gitignored"; exit 1; }
grep -q "^src/stories/ScreenshotIterateConcepts" .gitignore || { echo "FAIL: story not gitignored"; exit 1; }
[ -f .screenshot-iterate/INDEX.md ]
grep -q "checkout" .screenshot-iterate/INDEX.md
grep -q "60.*85" .screenshot-iterate/INDEX.md

echo "PASS"
