#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"; git init -q
SESSION_DIR=$("$REPO/scripts/screenshot.sh" session-init "x")
printf '\x89PNG\r\n\x1a\n' > "$SESSION_DIR/baseline.png"

MOCK_GEN=1 "$REPO/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION_DIR" \
  --round 1 \
  --prompt-1 "Bold: strong type, accent colors" --label-1 "Bold & expressive" \
  --prompt-2 "Minimal: whitespace, neutral palette" --label-2 "Minimal & restrained" \
  --prompt-3 "Editorial: grid-driven, content-first" --label-3 "Structured & editorial"

for n in 1 2 3; do
  [ -f "$SESSION_DIR/concepts/round-1/option-$n.png" ] || { echo "FAIL: option-$n missing"; exit 1; }
done

# options.json must be valid JSON with correct labels + prompts
jq -e '. | length == 3' "$SESSION_DIR/concepts/round-1/options.json" >/dev/null \
  || { echo "FAIL: options.json not array-of-3"; exit 1; }
jq -e '.[0].label == "Bold & expressive"' "$SESSION_DIR/concepts/round-1/options.json" >/dev/null \
  || { echo "FAIL: option 1 label wrong"; exit 1; }
jq -e '.[1].prompt | contains("Minimal")' "$SESSION_DIR/concepts/round-1/options.json" >/dev/null \
  || { echo "FAIL: option 2 prompt missing"; exit 1; }
jq -e '.[2].n == 3 and .[2].path == "option-3.png"' "$SESSION_DIR/concepts/round-1/options.json" >/dev/null \
  || { echo "FAIL: option 3 metadata wrong"; exit 1; }

echo "PASS"
