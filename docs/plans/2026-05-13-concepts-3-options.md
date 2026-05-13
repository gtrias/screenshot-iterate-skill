# Concepts Mode (3-Options Design Pick) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "3 design options" step to the screenshot-iterate skill so the user picks a design direction (with optional refinement) before any code changes.

**Architecture:** New Step 4a runs once per session (configurable). It generates 3 stylistically-distinct PNGs in parallel from the baseline screenshot, presents them inline with style-direction labels, accepts `N | refine N: <tweak> | regenerate` from the user, and persists the chosen direction. Subsequent iterations stay single-shot but inherit the chosen direction as a prompt prefix. All artifacts are persisted under `.screenshot-iterate/sessions/<timestamp>-<slug>/` (gitignored by default). Storybook integration is opt-in via auto-detection — adds a CSF3 concepts story if Storybook is present.

**Tech Stack:** Bash (existing `screenshot.sh`), shell parallelism via `&` + `wait`, JSON metadata via `jq` (already a dep on the API-key path), markdown SKILL.md prose.

---

## Constraints

- DO NOT change the `screenshot.sh capture` or `screenshot.sh generate` interfaces — extend, don't break.
- DO NOT increase `MAX_ITERATIONS` budget; concept rounds are separate from code-iteration count.
- DO NOT pass the rejected 2 options to `impeccable critique` — baseline + chosen only.
- KEEP backwards compat: `CONCEPTS_MODE=never` must reproduce the current single-shot flow exactly.
- Tests are bash-based (`bats` if available, else plain `bash -e` runner under `scripts/test/`).

---

## Task 1: Add concepts subcommand skeleton + session layout

**Files:**
- Modify: `scripts/screenshot.sh` (add `concepts` subcommand + `session_dir` helper)
- Create: `scripts/test/test_concepts_layout.sh`

**Step 1: Write the failing test**

```bash
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
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_concepts_layout.sh`
Expected: FAIL ("Unknown subcommand: session-init" or similar)

**Step 3: Implement `session-init` in `screenshot.sh`**

Add a new subcommand at the top of the case dispatch:

```bash
session_init() {
  local target_slug="$1"
  local stamp; stamp=$(date +%Y-%m-%d_%H-%M-%S)
  local root=".screenshot-iterate/sessions/${stamp}-${target_slug}"
  mkdir -p "$root/concepts" "$root/iterations"
  cat > "$root/meta.json" <<JSON
{
  "target": "$target_slug",
  "created_at": "$stamp",
  "rounds": [],
  "chosen": null,
  "scores": {}
}
JSON
  echo "$root"
}
```

Wire it into the case dispatch:
```bash
case "${1:-}" in
  session-init) shift; session_init "$@" ;;
  capture)      ... ;;
  generate)     ... ;;
  *) usage ;;
esac
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_concepts_layout.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_concepts_layout.sh
git commit -m "feat(concepts): add session-init subcommand + persistent layout"
```

---

## Task 2: Add `.gitignore` auto-installer

**Files:**
- Modify: `scripts/screenshot.sh` (extend `session_init` to ensure `.gitignore` entry)
- Create: `scripts/test/test_gitignore_install.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q
"$OLDPWD/scripts/screenshot.sh" session-init "homepage" > /dev/null
grep -q "^\.screenshot-iterate/" .gitignore || { echo "FAIL: .gitignore not updated"; exit 1; }
# Idempotency: second call must not duplicate
"$OLDPWD/scripts/screenshot.sh" session-init "another" > /dev/null
[ "$(grep -c '^\.screenshot-iterate/' .gitignore)" -eq 1 ] || { echo "FAIL: duplicated entry"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_gitignore_install.sh`
Expected: FAIL (`.gitignore not updated`)

**Step 3: Extend `session_init`**

After `mkdir -p ...`, before writing `meta.json`:

```bash
if [ -d .git ] && ! grep -qxF ".screenshot-iterate/" .gitignore 2>/dev/null; then
  echo ".screenshot-iterate/" >> .gitignore
fi
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_gitignore_install.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_gitignore_install.sh
git commit -m "feat(concepts): auto-add .screenshot-iterate/ to .gitignore"
```

---

## Task 3: Parallel 3-options generation subcommand

**Files:**
- Modify: `scripts/screenshot.sh` (add `concepts-generate` subcommand)
- Create: `scripts/test/test_concepts_generate.sh`

**Step 1: Write the failing test (mocked)**

The test stubs `gen_with_api_key` / `gen_with_codex` so we don't hit real APIs. Use a `MOCK_GEN=1` env that causes generation to copy the input to the output after a small sleep.

```bash
#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q
SESSION_DIR=$("$OLDPWD/scripts/screenshot.sh" session-init "x")
# create fake baseline
convert -size 10x10 xc:white "$SESSION_DIR/baseline.png" 2>/dev/null || \
  printf '\x89PNG\r\n\x1a\n' > "$SESSION_DIR/baseline.png"

MOCK_GEN=1 "$OLDPWD/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION_DIR" \
  --round 1 \
  --prompt-1 "Bold: strong type, accent colors" --label-1 "Bold & expressive" \
  --prompt-2 "Minimal: whitespace, neutral palette" --label-2 "Minimal & restrained" \
  --prompt-3 "Editorial: grid-driven, content-first" --label-3 "Structured & editorial"

for n in 1 2 3; do
  [ -f "$SESSION_DIR/concepts/round-1/option-$n.png" ] || { echo "FAIL: option-$n missing"; exit 1; }
done
grep -q '"label": "Bold & expressive"' "$SESSION_DIR/concepts/round-1/options.json" || \
  { echo "FAIL: options.json missing label"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_concepts_generate.sh`
Expected: FAIL (`Unknown subcommand: concepts-generate`)

**Step 3: Implement `concepts-generate`**

```bash
concepts_generate() {
  local session round
  local -a prompts labels
  prompts=("" "" ""); labels=("" "" "")
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --round)   round="$2"; shift 2 ;;
      --prompt-1) prompts[0]="$2"; shift 2 ;;
      --prompt-2) prompts[1]="$2"; shift 2 ;;
      --prompt-3) prompts[2]="$2"; shift 2 ;;
      --label-1)  labels[0]="$2"; shift 2 ;;
      --label-2)  labels[1]="$2"; shift 2 ;;
      --label-3)  labels[2]="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done
  local baseline="$session/baseline.png"
  local round_dir="$session/concepts/round-$round"
  mkdir -p "$round_dir"

  gen_one() {
    local idx="$1" prompt="$2" out="$3"
    if [ "${MOCK_GEN:-0}" = "1" ]; then
      cp "$baseline" "$out"
    else
      generate_dispatch "$baseline" "$prompt" "$out"
    fi
  }

  for i in 0 1 2; do
    gen_one "$i" "${prompts[$i]}" "$round_dir/option-$((i+1)).png" &
  done
  wait

  # Write options.json
  {
    echo "["
    for i in 0 1 2; do
      sep=","; [ "$i" = "2" ] && sep=""
      printf '  {"n": %d, "label": "%s", "prompt": %s, "path": "option-%d.png"}%s\n' \
        $((i+1)) "${labels[$i]}" "$(printf '%s' "${prompts[$i]}" | jq -Rs .)" $((i+1)) "$sep"
    done
    echo "]"
  } > "$round_dir/options.json"
}
```

Add to case dispatch: `concepts-generate) shift; concepts_generate "$@" ;;`

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_concepts_generate.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_concepts_generate.sh
git commit -m "feat(concepts): parallel 3-options generator with labels"
```

---

## Task 4: `concepts-choose` records the pick + updates meta.json

**Files:**
- Modify: `scripts/screenshot.sh`
- Create: `scripts/test/test_concepts_choose.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q
SESSION=$("$OLDPWD/scripts/screenshot.sh" session-init "x")
printf '\x89PNG' > "$SESSION/baseline.png"
MOCK_GEN=1 "$OLDPWD/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 p1 --label-1 Bold \
  --prompt-2 p2 --label-2 Minimal \
  --prompt-3 p3 --label-3 Editorial

"$OLDPWD/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 1 --option 2
[ -f "$SESSION/concepts/chosen.png" ] || { echo "FAIL: chosen.png not written"; exit 1; }
jq -e '.chosen.round == 1 and .chosen.option == 2 and .chosen.label == "Minimal"' "$SESSION/meta.json" \
  > /dev/null || { echo "FAIL: meta.json not updated"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_concepts_choose.sh`
Expected: FAIL (`Unknown subcommand: concepts-choose`)

**Step 3: Implement `concepts-choose`**

```bash
concepts_choose() {
  local session round option
  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --round)   round="$2"; shift 2 ;;
      --option)  option="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done
  local src="$session/concepts/round-$round/option-$option.png"
  [ -f "$src" ] || { echo "Option file not found: $src" >&2; exit 1; }
  cp "$src" "$session/concepts/chosen.png"

  local label
  label=$(jq -r --argjson n "$option" '.[] | select(.n == $n) | .label' \
    "$session/concepts/round-$round/options.json")

  local tmp; tmp=$(mktemp)
  jq --argjson r "$round" --argjson o "$option" --arg l "$label" \
    '.chosen = {round: $r, option: $o, label: $l}' "$session/meta.json" > "$tmp"
  mv "$tmp" "$session/meta.json"
}
```

Add to dispatch: `concepts-choose) shift; concepts_choose "$@" ;;`

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_concepts_choose.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_concepts_choose.sh
git commit -m "feat(concepts): record chosen option in session meta"
```

---

## Task 5: Storybook detection + concepts story emitter

**Files:**
- Modify: `scripts/screenshot.sh` (extend `concepts-generate` to call `emit_storybook_story` at end)
- Create: `scripts/test/test_storybook_emit.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q

# Case A: no storybook → no story file written
SESSION=$("$OLDPWD/scripts/screenshot.sh" session-init "no-sb")
printf '\x89PNG' > "$SESSION/baseline.png"
MOCK_GEN=1 "$OLDPWD/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 p --label-1 Bold --prompt-2 p --label-2 Minimal --prompt-3 p --label-3 Editorial
[ ! -e "src/stories/ScreenshotIterateConcepts.stories.tsx" ] || { echo "FAIL: story emitted without SB"; exit 1; }

# Case B: storybook present → story file written
mkdir -p .storybook src/stories
echo "{}" > .storybook/main.js
MOCK_GEN=1 "$OLDPWD/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 2 \
  --prompt-1 p --label-1 Bold --prompt-2 p --label-2 Minimal --prompt-3 p --label-3 Editorial
[ -f "src/stories/ScreenshotIterateConcepts.stories.tsx" ] || { echo "FAIL: story missing"; exit 1; }
grep -q "Bold" src/stories/ScreenshotIterateConcepts.stories.tsx || { echo "FAIL: label missing"; exit 1; }
grep -q "^src/stories/ScreenshotIterateConcepts" .gitignore || { echo "FAIL: story not gitignored"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_storybook_emit.sh`
Expected: FAIL

**Step 3: Implement `emit_storybook_story`**

```bash
detect_storybook() {
  [ -d .storybook ] && return 0
  [ -f package.json ] && jq -e '.devDependencies.storybook // .dependencies.storybook' \
    package.json >/dev/null 2>&1 && return 0
  return 1
}

emit_storybook_story() {
  local session="$1" round="$2"
  detect_storybook || return 0
  mkdir -p src/stories
  local story="src/stories/ScreenshotIterateConcepts.stories.tsx"
  local round_dir="$session/concepts/round-$round"

  {
    echo "// Auto-generated by screenshot-iterate. Do not edit by hand."
    echo "import type { Meta, StoryObj } from '@storybook/react';"
    echo ""
    echo "const Concept = ({ src, label }: { src: string; label: string }) => ("
    echo "  <figure style={{ margin: 0 }}>"
    echo "    <img src={src} alt={label} style={{ maxWidth: '100%', display: 'block' }} />"
    echo "    <figcaption style={{ marginTop: 8, fontFamily: 'system-ui' }}>{label}</figcaption>"
    echo "  </figure>"
    echo ");"
    echo ""
    echo "const meta: Meta<typeof Concept> = { title: 'screenshot-iterate/Concepts (round $round)', component: Concept };"
    echo "export default meta;"
    echo ""
    for n in 1 2 3; do
      label=$(jq -r ".[] | select(.n == $n) | .label" "$round_dir/options.json")
      rel="../../$round_dir/option-$n.png"
      echo "export const Option$n: StoryObj<typeof Concept> = { args: { src: '$rel', label: '$label' } };"
    done
  } > "$story"

  grep -qxF "src/stories/ScreenshotIterateConcepts.stories.tsx" .gitignore 2>/dev/null || \
    echo "src/stories/ScreenshotIterateConcepts.stories.tsx" >> .gitignore
}
```

Call it at the end of `concepts_generate`:
```bash
emit_storybook_story "$session" "$round"
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_storybook_emit.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_storybook_emit.sh
git commit -m "feat(concepts): emit Storybook concepts story when SB detected"
```

---

## Task 6: SKILL.md — add Step 4a + update prose

**Files:**
- Modify: `SKILL.md` (insert Step 4a, update Step 5 to reference `chosen.png`, document `CONCEPTS_MODE`)

**Step 1: Edits in SKILL.md**

Insert between current Step 3 and Step 4:

````markdown
### Step 3b: Initialize session

```bash
SESSION_DIR=$(screenshot.sh session-init "<target-slug>")
cp "$BASELINE" "$SESSION_DIR/baseline.png"
```

### Step 4a: Concept selection (3 options) — first iteration only

Triggered automatically on iteration 1 unless `CONCEPTS_MODE=never`.

1. Examine the baseline. Choose 3 **radically different** style directions adaptive to what the baseline lacks. Defaults: `Bold & expressive`, `Minimal & restrained`, `Structured & editorial`. Substitute if the baseline already embodies one (e.g., baseline is minimal → swap "Minimal" for "Maximal & dense").

2. Run parallel generation:

   ```bash
   screenshot.sh concepts-generate \
     --session "$SESSION_DIR" --round 1 \
     --prompt-1 "<full prompt for direction 1>" --label-1 "Bold & expressive" \
     --prompt-2 "<full prompt for direction 2>" --label-2 "Minimal & restrained" \
     --prompt-3 "<full prompt for direction 3>" --label-3 "Structured & editorial"
   ```

3. Read all 3 PNGs inline (use the Read tool on each `option-N.png`). Present:

   ```
   Option 1 — Bold & expressive
     <one-sentence description>
   Option 2 — Minimal & restrained
     <one-sentence description>
   Option 3 — Structured & editorial
     <one-sentence description>

   Reply: 1 | 2 | 3 | refine N: <tweak> | regenerate
   ```

4. Handle the response:
   - **`N`** (1-3): `screenshot.sh concepts-choose --session "$SESSION_DIR" --round <R> --option N`. Proceed to Step 5.
   - **`refine N: <tweak>`**: Craft a regen prompt grounded in all 3 PNGs (free to reference others, e.g., *"option 2 but with option 1's palette"*). Replace just option N in the current round and re-present.
   - **`regenerate`**: Increment round. Optionally ask for a direction hint. Generate 3 fresh options. **After 3 rounds**, warn: *"~12 images generated this session. Continue regenerating?"*

5. The chosen direction's label + prompt fragment is appended to the prompts used in iterations 2+ for continuity.
````

Update Step 5 to reference `$SESSION_DIR/concepts/chosen.png` as the "redesign" image (instead of the old single-shot output).

Add to the Auto-Detection section:

```markdown
### Concepts mode

- `CONCEPTS_MODE=first` (default) — 3-options pick on iter 1, single-shot after
- `CONCEPTS_MODE=always` — 3-options every iter (high cost)
- `CONCEPTS_MODE=never` — disable; reproduces pre-concepts behavior
```

**Step 2: Sanity check**

Read the file back, verify markdown headers nest correctly and no other steps reference the old `$REDESIGN` variable without falling through to `chosen.png`.

**Step 3: Commit**

```bash
git add SKILL.md
git commit -m "docs(concepts): document Step 4a, concepts mode, session layout"
```

---

## Task 7: Preflight update — surface concepts state

**Files:**
- Modify: `scripts/preflight.sh` (include `concepts_mode` in JSON output)
- Create: `scripts/test/test_preflight_concepts.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
out=$(CONCEPTS_MODE=always bash "$OLDPWD/scripts/preflight.sh" 2>/dev/null || true)
echo "$out" | jq -e '.concepts_mode == "always"' >/dev/null || { echo "FAIL: concepts_mode missing/wrong"; exit 1; }
out=$(bash "$OLDPWD/scripts/preflight.sh" 2>/dev/null || true)
echo "$out" | jq -e '.concepts_mode == "first"' >/dev/null || { echo "FAIL: default not 'first'"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_preflight_concepts.sh`
Expected: FAIL

**Step 3: Add to `preflight.sh`**

In the JSON emission, add:

```bash
CONCEPTS_MODE_VAL="${CONCEPTS_MODE:-first}"
# ... append to JSON: "concepts_mode": "$CONCEPTS_MODE_VAL"
```

Validate the value is one of `first|always|never`, else add to `errors` array.

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_preflight_concepts.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/preflight.sh scripts/test/test_preflight_concepts.sh
git commit -m "feat(preflight): expose concepts_mode in JSON output"
```

---

## Task 8: INDEX.md auto-update on session completion

**Files:**
- Modify: `scripts/screenshot.sh` (add `session-finalize` subcommand)
- Create: `scripts/test/test_index_update.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q
SESSION=$("$OLDPWD/scripts/screenshot.sh" session-init "homepage")
"$OLDPWD/scripts/screenshot.sh" session-finalize --session "$SESSION" --score-initial 62 --score-final 81
[ -f .screenshot-iterate/INDEX.md ] || { echo "FAIL: INDEX.md missing"; exit 1; }
grep -q "homepage" .screenshot-iterate/INDEX.md || { echo "FAIL: target missing"; exit 1; }
grep -q "62.*81" .screenshot-iterate/INDEX.md || { echo "FAIL: scores missing"; exit 1; }
echo "PASS"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/test/test_index_update.sh`
Expected: FAIL

**Step 3: Implement `session-finalize`**

```bash
session_finalize() {
  local session score_initial score_final
  while [ $# -gt 0 ]; do
    case "$1" in
      --session)       session="$2"; shift 2 ;;
      --score-initial) score_initial="$2"; shift 2 ;;
      --score-final)   score_final="$2"; shift 2 ;;
      *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
  done
  local target stamp
  target=$(jq -r '.target' "$session/meta.json")
  stamp=$(jq -r '.created_at' "$session/meta.json")
  local idx=".screenshot-iterate/INDEX.md"
  [ -f "$idx" ] || echo "# Screenshot-Iterate Session Log" > "$idx"
  printf -- "- %s — **%s** — %s → %s — \`%s\`\n" "$stamp" "$target" "$score_initial" "$score_final" "$session" >> "$idx"

  local tmp; tmp=$(mktemp)
  jq --argjson si "$score_initial" --argjson sf "$score_final" \
    '.scores = {initial: $si, final: $sf}' "$session/meta.json" > "$tmp"
  mv "$tmp" "$session/meta.json"
}
```

Add to dispatch.

**Step 4: Run test to verify it passes**

Run: `bash scripts/test/test_index_update.sh`
Expected: `PASS`

**Step 5: Commit**

```bash
git add scripts/screenshot.sh scripts/test/test_index_update.sh
git commit -m "feat(concepts): INDEX.md session log + finalize subcommand"
```

---

## Task 9: End-to-end smoke test (mocked)

**Files:**
- Create: `scripts/test/test_e2e_smoke.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
# Runs the full session lifecycle in MOCK_GEN mode with all features.
set -euo pipefail
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
cd "$TMP"; git init -q

# Pretend Storybook is present
mkdir -p .storybook && echo "{}" > .storybook/main.js

SESSION=$("$OLDPWD/scripts/screenshot.sh" session-init "checkout")
printf '\x89PNG' > "$SESSION/baseline.png"

MOCK_GEN=1 "$OLDPWD/scripts/screenshot.sh" concepts-generate \
  --session "$SESSION" --round 1 \
  --prompt-1 "p1" --label-1 Bold \
  --prompt-2 "p2" --label-2 Minimal \
  --prompt-3 "p3" --label-3 Editorial

"$OLDPWD/scripts/screenshot.sh" concepts-choose --session "$SESSION" --round 1 --option 3

"$OLDPWD/scripts/screenshot.sh" session-finalize \
  --session "$SESSION" --score-initial 60 --score-final 85

# Assertions
jq -e '.chosen.label == "Editorial"' "$SESSION/meta.json" >/dev/null
jq -e '.scores.final == 85' "$SESSION/meta.json" >/dev/null
[ -f "$SESSION/concepts/chosen.png" ]
[ -f src/stories/ScreenshotIterateConcepts.stories.tsx ]
grep -q "^.screenshot-iterate/" .gitignore
grep -q "^src/stories/ScreenshotIterateConcepts" .gitignore
echo "PASS"
```

**Step 2: Run**

Run: `bash scripts/test/test_e2e_smoke.sh`
Expected: `PASS`

**Step 3: Commit**

```bash
git add scripts/test/test_e2e_smoke.sh
git commit -m "test(concepts): end-to-end smoke covering full session lifecycle"
```

---

## Task 10: Update README.md with concepts mode example

**Files:**
- Modify: `README.md`

Add a section "Concepts Mode (3-option pick)" after current usage, with:
- One-paragraph overview
- The `Option 1/2/3` prompt example
- `CONCEPTS_MODE` env var table
- Folder layout diagram of `.screenshot-iterate/sessions/...`
- Screenshot of a Storybook concepts page (optional, deferred)

**Commit:**

```bash
git add README.md
git commit -m "docs(readme): document concepts mode + session layout"
```

---

## Out of Scope (explicitly NOT in this plan)

- Composite "mix" of two options (decided: collapse into refine-with-references in Q12)
- HTML-based comparison viewer (rejected in Q3 — inline Read is enough)
- Cross-session concept reuse / "remember last pick for this target" (future enhancement)
- Pinning a concept as a permanent baseline alternative
- Cost reporting / token tracking beyond the soft warning

---

## Verification Checklist

- [ ] `CONCEPTS_MODE=never bash scripts/screenshot.sh ...` reproduces single-shot output (no concept files generated)
- [ ] All 9 test scripts pass: `for f in scripts/test/*.sh; do bash "$f" || exit 1; done`
- [ ] `.gitignore` contains `.screenshot-iterate/` after first run, no duplicates after second run
- [ ] Storybook story only exists when `.storybook/` or package.json declares storybook
- [ ] `meta.json` is valid JSON after each subcommand (`jq . meta.json >/dev/null`)
- [ ] SKILL.md Step 4a renders correctly in markdown preview
