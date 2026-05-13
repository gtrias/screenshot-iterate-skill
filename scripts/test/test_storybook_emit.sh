#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q

# Case A: no storybook → no story file
SESSION=$("$REPO/scripts/screenshot.sh" session-init "no-sb")
printf '\x89PNG\r\n\x1a\n' > "$SESSION/baseline.png"
MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 p --label-1 Bold --prompt-2 p --label-2 Minimal --prompt-3 p --label-3 Editorial
[ ! -e "src/stories/ScreenshotIterateConcepts.stories.tsx" ] || { echo "FAIL: story emitted without SB"; exit 1; }

# Case B: .storybook dir present → story written
mkdir -p .storybook
echo "module.exports = {};" > .storybook/main.js
MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 2 \
  --prompt-1 p --label-1 Bold --prompt-2 p --label-2 Minimal --prompt-3 p --label-3 Editorial
[ -f "src/stories/ScreenshotIterateConcepts.stories.tsx" ] || { echo "FAIL: story missing"; exit 1; }
grep -q "Bold" src/stories/ScreenshotIterateConcepts.stories.tsx || { echo "FAIL: label Bold missing"; exit 1; }
grep -q "Minimal" src/stories/ScreenshotIterateConcepts.stories.tsx || { echo "FAIL: label Minimal missing"; exit 1; }
grep -q "Editorial" src/stories/ScreenshotIterateConcepts.stories.tsx || { echo "FAIL: label Editorial missing"; exit 1; }
grep -q "^src/stories/ScreenshotIterateConcepts" .gitignore || { echo "FAIL: story not gitignored"; exit 1; }
grep -q "round-2" src/stories/ScreenshotIterateConcepts.stories.tsx || { echo "FAIL: round number not reflected"; exit 1; }

# Case C: detection via package.json devDependencies
rm -rf .storybook src/stories
echo '{"devDependencies":{"storybook":"^8.0.0"}}' > package.json
MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 3 \
  --prompt-1 p --label-1 Bold --prompt-2 p --label-2 Minimal --prompt-3 p --label-3 Editorial
[ -f "src/stories/ScreenshotIterateConcepts.stories.tsx" ] || { echo "FAIL: story missing on pkg.json detect"; exit 1; }

# Case D: idempotency on gitignore
grep_count=$(grep -c "^src/stories/ScreenshotIterateConcepts" .gitignore)
[ "$grep_count" -eq 1 ] || { echo "FAIL: gitignore duplicated"; exit 1; }

echo "PASS"
