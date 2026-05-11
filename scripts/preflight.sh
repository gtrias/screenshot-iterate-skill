#!/usr/bin/env bash
# preflight.sh — Screenshot-Iterate dependency validator
# Outputs JSON status report. Exit 1 on blocking errors, exit 0 if all clear.

set -euo pipefail

openai_ok=false
if [ -n "${OPENAI_API_KEY:-}" ]; then
  openai_ok=true
fi

# Detect screenshot tool (priority order)
screenshot_tool="none"
playwright_version=""
pinchtab_ok=false

if command -v npx &>/dev/null; then
  playwright_version=$(npx playwright --version 2>/dev/null || echo "")
fi

if [ -n "$playwright_version" ]; then
  screenshot_tool="playwright"
elif command -v curl &>/dev/null; then
  if curl -sf http://localhost:9867/health >/dev/null 2>&1; then
    pinchtab_ok=true
    screenshot_tool="pinchtab"
  fi
fi

# Dev server URL (env override or default)
dev_server_url="${SCREENSHOT_ITERATE_URL:-http://localhost:3000}"

# Impeccable skill check
impeccable_ok=false
if [ -f "$HOME/.pi/agent/skills/impeccable/SKILL.md" ]; then
  impeccable_ok=true
elif [ -f "$HOME/.agents/skills/impeccable/SKILL.md" ]; then
  impeccable_ok=true
fi

# Max iterations (env override or default)
max_iter="${MAX_ITERATIONS:-5}"

# Collect blocking errors
errors=()
if [ "$openai_ok" = false ]; then
  errors+=("\"OPENAI_API_KEY not set\"")
fi
if [ "$screenshot_tool" = "none" ]; then
  errors+=("\"No screenshot tool found (need Playwright or pinchtab)\"")
fi
if [ "$impeccable_ok" = false ]; then
  errors+=("\"impeccable skill not found (check ~/.pi/agent/skills/impeccable/ and ~/.agents/skills/impeccable/)\"")
fi

# Build JSON
errors_json="[]"
if [ ${#errors[@]} -gt 0 ]; then
  errors_json=$(printf ',%s' "${errors[@]}" | sed 's/^,//')
fi

cat <<EOF
{
  "openai_api_key": $openai_ok,
  "screenshot_tool": "$screenshot_tool",
  "dev_server_url": "$dev_server_url",
  "impeccable": $impeccable_ok,
  "max_iterations": $max_iter,
  "errors": [$errors_json]
}
EOF

if [ ${#errors[@]} -gt 0 ]; then
  exit 1
fi
exit 0
