#!/usr/bin/env bash
# screenshot.sh — Screenshot capture + GPT Image 2 generation helper
# Usage:
#   screenshot.sh capture <url> <output_path> [playwright|pinchtab]
#   screenshot.sh generate <image_path> --prompt "<text>" [--size WxH] [--model gpt-image-2]

set -euo pipefail

usage() {
  echo "Usage:"
  echo "  $0 capture <url> <output_path> [playwright|pinchtab]"
  echo "  $0 generate <image_path> --prompt \"<text>\" [--size 1536x1024] [--model gpt-image-2]"
  exit 1
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
    model="gpt-image-2"
    output_path="${image%.png}-redesign.png"

    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt) prompt="$2"; shift 2 ;;
        --size)   size="$2"; shift 2 ;;
        --model)  model="$2"; shift 2 ;;
        *)        shift ;;
      esac
    done

    if [ -z "$prompt" ]; then
      echo "ERROR: --prompt required for generate mode" >&2
      exit 1
    fi

    curl -s https://api.openai.com/v1/images/edits \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -F "image=@$image" \
      -F "prompt=$prompt" \
      -F "model=$model" \
      -F "size=$size" \
      -o "$output_path" 2>/dev/null

    if [ -s "$output_path" ]; then
      echo "$output_path"
    else
      echo "ERROR: GPT Image 2 generation failed or returned empty file" >&2
      rm -f "$output_path"
      exit 1
    fi
    ;;

  *)
    usage
    ;;
esac
