---
name: screenshot-iterate
description: Iterative design improvement loop. Takes E2E screenshots of target screens, generates improved designs via GPT Image 2, reviews with impeccable critique, implements changes, and repeats. Use when refining UI design of any screen or component.
user-invocable: true
argument-hint: "[target: URL path, component file, or screen description]"
---

# Screenshot-Driven Design Iteration

Capture a screen → generate an improved design with GPT Image 2 → critique with impeccable → implement changes → re-capture → repeat.

Distributable skill that adapts to any project via auto-detection. No presets needed.

## Hard Dependencies (all required)

| Dependency | What it provides | How the agent checks |
|---|---|---|
| Image generation method* | GPT Image 2 API access | `preflight.sh` |
| Screenshot tool | Capture live UI | Auto-detected: Playwright > pinchtab |
| Dev server running | Target screen to capture | Auto-detected from running processes or env |
| impeccable skill | Critique engine | Checked in preflight |

\* **Image generation** — need one of:
- **Codex CLI** (`codex`) + ChatGPT Plus/Pro subscription → zero extra cost, reuses your plan
- **OpenAI API key** (`OPENAI_API_KEY` env var) → per-call billing on your API account

If both are available, the agent asks which to use. If only one, it auto-selects.
Set `IMAGE_GEN_METHOD=codex|api_key` to skip the prompt and force a method.

## Auto-Detection (3 axes)

### Screenshot tool (priority order)

1. **Playwright** — `npx playwright --version` succeeds
2. **pinchtab** — `curl localhost:9867/health` returns OK
3. **Fallback** — ask user for a screenshot command

### Dev server URL

1. Running process detection (lsof / ss / netstat)
2. Common ports from `package.json` scripts (`5173`, `3000`, `8080`, `4321`)
3. Env override: `SCREENSHOT_ITERATE_URL=http://localhost:5173`
4. Default: `http://localhost:3000`

### Iteration control

- **Max iterations:** env `MAX_ITERATIONS` (default: 5)
- **Stall detection:** 2 consecutive iterations without score improvement → warn + ask user

### Concepts mode

- `CONCEPTS_MODE=first` (default) — 3-options pick on iteration 1, single-shot after
- `CONCEPTS_MODE=always` — 3-options every iteration (higher cost; warns after 3 regen rounds in a session)
- `CONCEPTS_MODE=never` — disable concept selection; reproduces pre-concepts behavior

Setting `CONCEPTS_MODE=never` reproduces the pre-concepts single-shot behavior end-to-end — no session dir, no concept rounds, identical to versions before this feature.

## Workflow

### Step 1: Preflight

Run the preflight check and block if errors exist:

```bash
SKILL_DIR=$(find "$HOME" -maxdepth 4 -path "*/screenshot-iterate/scripts/preflight.sh" | head -1)
"$SKILL_DIR/../preflight.sh" || { echo "Preflight failed. Fix dependencies first."; exit; }
```

If preflight fails, stop and report which dependencies are missing. Do not proceed.

### Step 2: Identify the target

Determine what to improve. If the user didn't specify, ask one question:

> Which screen or component should I iterate on? Options: a URL path (e.g., `/p/slug`), a component file (e.g., `src/components/Header.tsx`), or a description (e.g., "the pricing page")

Store the detected tool and target for use in later steps.

### Step 3: Capture baseline screenshot

```bash
mkdir -p /tmp/screenshot-iterate/session-$RANDOM
BASELINE="/tmp/screenshot-iterate/session-$RANDOM/baseline.png"
screenshot.sh capture "$TARGET_URL" "$BASELINE" "$TOOL"
```

Read the screenshot file to understand the current state of the UI.

### Step 3b: Initialize session

```bash
SESSION_DIR=$(screenshot.sh session-init "<target-slug>")
cp "$BASELINE" "$SESSION_DIR/baseline.png"
```

The session dir persists under `.screenshot-iterate/sessions/<timestamp>-<target-slug>/` and is auto-added to `.gitignore`. All concept rounds, the chosen option, and iteration screenshots live under this dir for the rest of the loop.

### Step 4a: Concept selection (3 options)

Triggered on iteration 1 only by default (`CONCEPTS_MODE=first`). Skipped entirely when `CONCEPTS_MODE=never`. Run every iteration when `CONCEPTS_MODE=always`.

**1. Choose 3 radically different style directions.** Adaptive to baseline weaknesses. Defaults:

- **Bold & expressive** — strong color, large type, generous contrast
- **Minimal & restrained** — neutral palette, tight type scale, lots of negative space
- **Structured & editorial** — grid-forward, magazine-style hierarchy, intentional rules and dividers

Swap any default if the baseline already embodies that direction (e.g., baseline is already minimal → replace "Minimal" with another contrasting direction).

**2. Generate all 3 options in one call:**

```bash
screenshot.sh concepts-generate \
  --session "$SESSION_DIR" --round 1 \
  --prompt-1 "<bold & expressive prompt>" --label-1 "Bold & expressive" \
  --prompt-2 "<minimal & restrained prompt>" --label-2 "Minimal & restrained" \
  --prompt-3 "<structured & editorial prompt>" --label-3 "Structured & editorial"
```

**3. Read all 3 option PNGs inline** using the Read tool on each `$SESSION_DIR/concepts/round-<R>/option-1.png`, `option-2.png`, `option-3.png`.

**4. Present to the user:**

```
Option 1 — Bold & expressive: <1-sentence description>
Option 2 — Minimal & restrained: <1-sentence description>
Option 3 — Structured & editorial: <1-sentence description>

Reply: 1 | 2 | 3 | refine N: <tweak> | regenerate
```

**5. Handle the response:**

- `N` → `screenshot.sh concepts-choose --session "$SESSION_DIR" --round <R> --option N`; proceed to Step 5.
- `refine N: <tweak>` → craft a regen prompt referencing all 3 PNGs (e.g., "option 2 but with option 1's palette"); replace just option N in the current round, then re-present.
- `regenerate` → increment round, generate a fresh 3 options. After 3 rounds (~12 images), warn the user about cost.

Note: subsequent iterations (2+) use single-shot generation prefixed with the chosen direction for continuity, not the 3-options flow (unless `CONCEPTS_MODE=always`).

### Step 4: Generate improved design via GPT Image 2

Craft a specific prompt based on what needs improvement. Run:

```bash
REDESIGN=$(screenshot.sh generate "$BASELINE" \
  --prompt "<specific, concrete improvements>" \
  --model gpt-image-2)
```

Read the generated redesign image to understand the design direction.

**Prompt templates (pick the matching category, personalize from there):**

| Category | Base prompt |
|---|---|
| **Spacing** | "Redesign focusing on spacing and layout rhythm. Increase whitespace between sections for breathing room. Use consistent 8px grid spacing throughout. Improve vertical hierarchy with clear padding gaps." |
| **Typography** | "Redesign focusing on typography hierarchy. Make headings bolder and larger with clear contrast against body text. Ensure body text stays at 16px minimum. Improve line height and letter spacing for readability." |
| **Color** | "Redesign focusing on color palette and visual weight. Use brand accent colors strategically — not everywhere. Maintain good contrast ratios (≥4.5:1) on all text. Subtle background tints instead of pure white or black." |
| **Layout** | "Redesign focusing on layout structure. Improve alignment, grid consistency, and visual flow between elements. Fix any asymmetrical or unbalanced arrangements while maintaining all functionality." |
| **Polish** | "Final polish pass. Refine micro-details: border radius consistency, subtle shadows, transition states, hover interactions. Make alignments pixel-perfect. Remove any remaining visual noise." |

**How to personalize:** Add 1-2 sentences referencing what's currently wrong and what you want specifically different. Example: *"[spacing prompt]. The CTA button feels crammed against the heading — add more vertical gap between them."*

### Step 5: Critique with impeccable

Invoke `$impeccable critique` on the current implementation, passing both screenshots as reference:

- Current screenshot = baseline
- GPT Image 2 output = redesign direction

When concepts mode is active, the redesign image is `$SESSION_DIR/concepts/chosen.png` (written by `concepts-choose`). Pass baseline + `chosen.png` only — do **NOT** pass the rejected options to impeccable critique.

Ask critique to focus on the **delta** — what specific CSS/Tailwind/code changes would move the current UI toward the improved design. Extract actionable items:

- Exact spacing values (padding, gap, margin)
- Color values (hex/oklch)
- Font size changes (text-sm → text-base, etc.)
- Border radius, shadow, opacity changes
- Layout shifts (flex direction, grid columns, alignment)

### Step 6: Implement one category of changes

Based on the critique output:

1. Identify the exact component files that need changes
2. Apply changes for **one category only** (see Iteration Principles)
3. Use project conventions (Tailwind classes, styled-components, CSS modules — whatever the project uses)
4. Do NOT change behavior, only presentation

### Step 7: Re-screenshot and compare

Take a new screenshot of the same target. Compare old vs new:

- Did the changes improve the identified issues?
- Are there regressions in other areas?
- Does it move toward the GPT Image 2 direction?

If scores improved → loop back to Step 4 with the next category.
If no improvement (stall) or max iterations reached → produce final report.

### Loop completion report

When the loop ends, output:

```
Loop completed (N/MAX_ITERATIONS iterations)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Screen: <target description>
Scores: <initial> → <final> (+delta)
Categories resolved: spacing ✓ | typography ✓ | color ✗ | ...
Commit? [y/n] "chore(ui): redesign <target> - N iterations, score X→Y"
```

## Iteration Principles

- **One change category at a time** — spacing → typography → color → polish. Never mix categories in one iteration.
- **Screenshot before AND after** — always have visual proof of each step.
- **GPT Image 2 = direction, impeccable = specifics** — the generated image shows where to go, the critique tells you how to get there in code.
- **Preserve functionality** — never change behavior, only presentation.
- **Commit at each stable improvement** — small, reversible steps.
- **Trust the critique scores** — if heuristic scores improve, you are on the right track.

## Script Reference

Scripts live in `scripts/` alongside this SKILL.md.

### `preflight.sh`

Validates all dependencies. Outputs JSON:

```json
{
  "openai_api_key": true,
  "screenshot_tool": "playwright",
  "dev_server_url": "http://localhost:5173",
  "impeccable": true,
  "max_iterations": 5,
  "errors": []
}
```

Exit 0 = all clear. Exit 1 = blocking errors in `errors` array.

### `screenshot.sh`

Modes:

| Mode | Command | Output |
|---|---|---|
| `capture` | `screenshot.sh capture <url> <output.png> [tool]` | Screenshot file |
| `generate` | `screenshot.sh generate <image.png> --prompt "..." [--method codex\|api_key]` | Path to redesign.png (stdout) |
| `session-init` | `screenshot.sh session-init <target-slug>` | Session dir path on stdout |
| `concepts-generate` | `screenshot.sh concepts-generate --session <dir> --round <N> --prompt-1 ... --label-1 ... --prompt-2 ... --label-2 ... --prompt-3 ... --label-3 ...` | Writes 3 PNGs + options.json under `<session>/concepts/round-<N>/`; emits Storybook story if SB detected |
| `concepts-choose` | `screenshot.sh concepts-choose --session <dir> --round <N> --option <1\|2\|3>` | Writes `chosen.png`, updates `meta.json` |

Both detect tools automatically if not specified. Use env vars:
- `IMAGE_GEN_METHOD=codex|api_key` — force method (default: auto-detect)
- `SCREENSHOT_ITERATE_URL` — dev server URL override
- `SCREENSHOT_GENERATE_SIZE` — image size for API key method (ignored by codex)
