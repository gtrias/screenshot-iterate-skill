#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# Default → "first"
out=$(bash "$REPO/scripts/preflight.sh" 2>/dev/null || true)
echo "$out" | jq -e '.concepts_mode == "first"' >/dev/null \
  || { echo "FAIL: default concepts_mode should be 'first'"; echo "$out"; exit 1; }

# Explicit "always"
out=$(CONCEPTS_MODE=always bash "$REPO/scripts/preflight.sh" 2>/dev/null || true)
echo "$out" | jq -e '.concepts_mode == "always"' >/dev/null \
  || { echo "FAIL: CONCEPTS_MODE=always not reflected"; echo "$out"; exit 1; }

# Explicit "never"
out=$(CONCEPTS_MODE=never bash "$REPO/scripts/preflight.sh" 2>/dev/null || true)
echo "$out" | jq -e '.concepts_mode == "never"' >/dev/null \
  || { echo "FAIL: CONCEPTS_MODE=never not reflected"; echo "$out"; exit 1; }

# Invalid value → error in errors[], non-zero exit
set +e
out=$(CONCEPTS_MODE=bogus bash "$REPO/scripts/preflight.sh" 2>/dev/null)
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL: invalid CONCEPTS_MODE should exit non-zero"; exit 1; }
echo "$out" | jq -e '.errors | map(select(test("CONCEPTS_MODE"; "i"))) | length > 0' >/dev/null \
  || { echo "FAIL: invalid CONCEPTS_MODE should add to errors[]"; echo "$out"; exit 1; }

echo "PASS"
