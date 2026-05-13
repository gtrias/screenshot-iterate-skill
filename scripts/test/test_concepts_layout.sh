#!/usr/bin/env bash
# scripts/test/test_concepts_layout.sh
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"
"$OLDPWD/scripts/screenshot.sh" session-init "pricing-page" > sess.txt
SESSION_DIR=$(cat sess.txt)
[ -d "$SESSION_DIR" ] || { echo "FAIL: session dir not created"; exit 1; }
[ -d "$SESSION_DIR/concepts" ] || { echo "FAIL: concepts/ missing"; exit 1; }
[ -d "$SESSION_DIR/iterations" ] || { echo "FAIL: iterations/ missing"; exit 1; }
[ -f "$SESSION_DIR/meta.json" ] || { echo "FAIL: meta.json missing"; exit 1; }
grep -q '"target": "pricing-page"' "$SESSION_DIR/meta.json" || { echo "FAIL: target not in meta"; exit 1; }
echo "PASS"
