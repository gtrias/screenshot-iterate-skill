#!/usr/bin/env bash
# screenshot.sh — Screenshot capture + GPT Image 2 generation helper
# Usage:
#   screenshot.sh capture <url> <output_path> [playwright|pinchtab]
#   screenshot.sh generate <image_path> --prompt "<text>" [--size WxH] [--method codex|api_key]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage:"
  echo "  $0 capture <url> <output_path> [playwright|pinchtab]"
  echo "  $0 generate <image_path> --prompt \"<text>\" [--size 1536x1024] [--method codex|api_key]"
  echo "  $0 session-init <target_slug>"
  exit 1
}

session_init() {
  local target_slug="$1"
  local stamp; stamp=$(date +%Y-%m-%d_%H-%M-%S)
  local root=".screenshot-iterate/sessions/${stamp}-${target_slug}"
  mkdir -p "$root/concepts" "$root/iterations"
  if [ -d .git ] && ! grep -qxF ".screenshot-iterate/" .gitignore 2>/dev/null; then
    # Ensure the file ends with a newline before appending
    if [ -s .gitignore ] && [ "$(tail -c1 .gitignore)" != "" ]; then
      echo "" >> .gitignore
    fi
    echo ".screenshot-iterate/" >> .gitignore
  fi
  jq -n --arg target "$target_slug" --arg created_at "$stamp" \
    '{target: $target, created_at: $created_at, chosen: null, scores: {}}' \
    > "$root/meta.json"
  echo "$root"
}

detect_tool() {
  if npx playwright --version >/dev/null 2>&1; then
    echo "playwright"
  elif curl -sf http://localhost:9867/health >/dev/null 2>&1; then
    echo "pinchtab"
  else
    echo "none"
  fi
}

detect_img_method() {
  openai_ok=false
  codex_ok=false

  [ -n "${OPENAI_API_KEY:-}" ] && openai_ok=true
  command -v codex >/dev/null 2>&1 && [ -d ~/.codex ] && codex_ok=true

  if [ "$openai_ok" = true ] && [ "$codex_ok" = true ]; then
    echo "both"
  elif [ "$codex_ok" = true ]; then
    echo "codex"
  elif [ "$openai_ok" = true ]; then
    echo "api_key"
  else
    echo "none"
  fi
}

gen_with_api_key() {
  local image="$1" prompt="$2" size="$3" out="$4" model="${5:-gpt-image-2}"

  curl -s https://api.openai.com/v1/images/edits \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -F "image=@$image" \
    -F "prompt=$prompt" \
    -F "model=$model" \
    -F "size=$size" \
    -o "$out" 2>/dev/null

  if [ -s "$out" ]; then
    echo "$out"
    return 0
  else
    rm -f "$out"
    return 1
  fi
}

gen_with_codex() {
  local image="$1" prompt="$2" out="$3" timeout_sec="${4:-300}"

  SESSIONS_ROOT="$HOME/.codex/sessions"
  mkdir -p "$SESSIONS_ROOT"

  before="$(mktemp)"; after="$(mktemp)"
  stdout_log="$(mktemp)"; stderr_log="$(mktemp)"
  trap 'rm -f "$before" "$after" "$stdout_log" "$stderr_log"' EXIT

  find "$SESSIONS_ROOT" -type f -name 'rollout-*.jsonl' -print 2>/dev/null | sort > "$before" || true

  instruction="Use the imagegen tool to generate the image for the following request. Use the attached image as visual reference / input for image-to-image.
Requirements: generate the image directly, return only the image, no explanation.

Request:
$prompt"

  # Timeout command detection
  TO=""
  if   command -v timeout  >/dev/null 2>&1; then TO="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then TO="gtimeout"
  fi

  args=(exec --skip-git-repo-check --sandbox read-only --color never --enable image_generation -i "$image")

  set +e
  if [[ -n "$TO" ]]; then
    printf '%s' "$instruction" | "$TO" "$timeout_sec" codex "${args[@]}" >"$stdout_log" 2>"$stderr_log"
  else
    printf '%s' "$instruction" | codex "${args[@]}" >"$stdout_log" 2>"$stderr_log"
  fi
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "codex exec failed (exit=$rc)" >&2
    return 5
  fi

  find "$SESSIONS_ROOT" -type f -name 'rollout-*.jsonl' -print 2>/dev/null | sort > "$after" || true

  new_sessions_file="$(mktemp)"
  comm -13 "$before" "$after" > "$new_sessions_file" || true

  if [[ ! -s "$new_sessions_file" ]]; then
    echo "No new session file detected" >&2
    return 6
  fi

  set +e
  python3 "$SCRIPT_DIR/extract_image.py" "$out" "$new_sessions_file"
  py_rc=$?
  set -e

  rm -f "$new_sessions_file"

  if [[ $py_rc -ne 0 ]]; then
    echo "Image payload not found in session file" >&2
    return 7
  fi

  echo "$out"
  return 0
}

# -- Main --
[ $# -lt 1 ] && usage
mode="$1"

case "$mode" in
  capture)
    [ $# -lt 3 ] && usage
    shift
    url="$1"
    output="$2"
    tool="${3:-$(detect_tool)}"

    mkdir -p "$(dirname "$output")"

    case "$tool" in
      playwright)
        SURL="$url" SOUT="$output" node -e "
          require('playwright').chromium.launch({headless:true}).then(async b => {
            const p = await b.newPage();
            await p.goto(process.env.SURL,{waitUntil:'networkidle'});
            await p.screenshot({path:process.env.SOUT,fullPage:false});
            await b.close();
          });
        " 2>/dev/null || echo "ERROR: Playwright capture failed"
        ;;
      pinchtab)
        curl -sf "http://localhost:9867/screenshot?url=$(echo "$url" | sed 's/ /%20/g')" \
          > "$output" 2>/dev/null || echo "ERROR: Pinchtab capture failed"
        ;;
      *)
        echo "ERROR: No screenshot tool available. Install Playwright or start pinchtab." >&2
        exit 1
        ;;
    esac
    ;;

  generate)
    [ $# -lt 3 ] && usage
    shift
    image="$1"

    prompt=""
    size="${SCREENSHOT_GENERATE_SIZE:-1536x1024}"
    method="${IMAGE_GEN_METHOD:-auto}"
    output_path="${image%.png}-redesign.png"

    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt)  prompt="$2"; shift 2 ;;
        --size)    size="$2"; shift 2 ;;
        --method)  method="$2"; shift 2 ;;
        *)         shift ;;
      esac
    done

    if [ -z "$prompt" ]; then
      echo "ERROR: --prompt required for generate mode" >&2
      exit 1
    fi

    # Resolve method
    available=$(detect_img_method)

    case "$method" in
      codex|api_key)
        chosen="$method"
        ;;
      auto|both)
        if [ "$available" = "both" ]; then
          echo "Both methods available: Codex CLI (free via ChatGPT subscription)"
          echo "  or OpenAI API key (per-call billing)."
          echo "Which would you like to use?"
          echo ""
          read -r choice || true
          case "${choice,,}" in
            codex*) chosen="codex" ;;
            api*)   chosen="api_key" ;;
            1)      chosen="codex" ;;
            2)      chosen="api_key" ;;
            *)      echo "Defaulting to codex (no extra cost)" && chosen="codex" ;;
          esac
        elif [ "$available" = "codex" ]; then
          chosen="codex"
        elif [ "$available" = "api_key" ]; then
          chosen="api_key"
        else
          echo "ERROR: No image generation method available (need OPENAI_API_KEY or codex CLI)" >&2
          exit 1
        fi
        ;;
      *)
        echo "ERROR: Unknown method '$method'. Use 'codex', 'api_key', or 'auto'." >&2
        exit 1
        ;;
    esac

    # Execute chosen method
    case "$chosen" in
      codex)
        set +e
        result=$(gen_with_codex "$image" "$prompt" "$output_path")
        rc=$?
        set -e
        if [ $rc -eq 0 ]; then
          echo "$result"
        else
          rm -f "$output_path"
          exit $rc
        fi
        ;;
      api_key)
        set +e
        result=$(gen_with_api_key "$image" "$prompt" "$size" "$output_path")
        rc=$?
        set -e
        if [ $rc -eq 0 ]; then
          echo "$result"
        else
          exit 1
        fi
        ;;
    esac
    ;;

  session-init)
    shift
    [ $# -lt 1 ] && usage
    session_init "$@"
    ;;

  *)
    usage
    ;;
esac
