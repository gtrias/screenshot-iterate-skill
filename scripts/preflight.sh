#!/usr/bin/env bash
# preflight.sh — Screenshot-Iterate dependency validator
# Outputs JSON status report. Exit 1 on blocking errors, exit 0 if all clear.

set -euo pipefail

# -- Image generation methods --
openai_api_ok=false
if [ -n "${OPENAI_API_KEY:-}" ]; then
  openai_api_ok=true
fi

codex_ok=false
if command -v codex >/dev/null 2>&1; then
  # Check if codex is logged in (session file exists)
  if ls ~/.codex/sessions/ 2>/dev/null | head -1 >/dev/null 2>&1 || \
     codex status >/dev/null 2>&1 || \
     [ -d ~/.codex ]; then
    codex_ok=true
  fi
fi

# -- Screenshot tool (priority order) --
screenshot_tool="none"

if command -v npx &>/dev/null && npx playwright --version >/dev/null 2>&1; then
  screenshot_tool="playwright"
elif command -v curl &>/dev/null && curl -sf http://localhost:9867/health >/dev/null 2>&1; then
  screenshot_tool="pinchtab"
fi

# -- Dev server URL (env override or default) --
dev_server_url="${SCREENSHOT_ITERATE_URL:-http://localhost:3000}"

# -- Impeccable skill check --
impeccable_ok=false
if [ -f "$HOME/.pi/agent/skills/impeccable/SKILL.md" ]; then
  impeccable_ok=true
elif [ -f "$HOME/.agents/skills/impeccable/SKILL.md" ]; then
  impeccable_ok=true
fi

# -- Max iterations (env override or default) --
max_iter="${MAX_ITERATIONS:-5}"

# -- Image generation method selection --
img_method="auto"
if [ "$openai_api_ok" = true ] && [ "$codex_ok" = true ]; then
  img_method="ask"
elif [ "$codex_ok" = true ]; then
  img_method="codex"
elif [ "$openai_api_ok" = true ]; then
  img_method="api_key"
else
  img_method="none"
fi

# -- Collect blocking errors --
errors=()
if [ "$img_method" = "none" ]; then
  errors+=("\"No image generation method available (need OPENAI_API_KEY or codex CLI)\"")
fi
if [ "$screenshot_tool" = "none" ]; then
  errors+=("\"No screenshot tool found (need Playwright or pinchtab)\"")
fi
if [ "$impeccable_ok" = false ]; then
  errors+=("\"impeccable skill not found (check ~/.pi/agent/skills/impeccable/ and ~/.agents/skills/impeccable/)\"")
fi

# -- Build JSON --
errors_json="[]"
error_count=${#errors[@]}
if [ "$error_count" -gt 0 ]; then
  errors_json=$(printf ',%s' "${errors[@]}" | sed 's/^,//')
fi

# -- Build JSON --
error_items=""
if [ ${#errors[@]} -gt 0 ]; then
  error_items=$(printf ',%s' "${errors[@]}" | sed 's/^,//')
fi

cat <<EOF
{
  "openai_api_key": $openai_api_ok,
  "codex_cli": $codex_ok,
  "image_method": "$img_method",
  "screenshot_tool": "$screenshot_tool",
  "dev_server_url": "$dev_server_url",
  "impeccable": $impeccable_ok,
  "max_iterations": $max_iter,
  "errors": [$error_items]
}
EOF

if [ ${#errors[@]} -gt 0 ]; then
  exit 1
fi
exit 0
