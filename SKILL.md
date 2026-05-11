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
| `OPENAI_API_KEY` env var | GPT Image 2 API access | `preflight.sh` |
| Screenshot tool | Capture live UI | Auto-detected: Playwright > pinchtab |
| Dev server running | Target screen to capture | Auto-detected from running processes or env |
| impeccable skill | Critique engine | Checked in preflight |

If any hard dependency is missing, the skill stops with a clear error. No fallback.

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

## Workflow

### Step 1: Preflight

Run the preflight check and block if errors exist:

```bash
SKILL_DIR=$(find "$HOME" -maxdepth 4 -path "*/screenshot-iterate/scripts/preflight.sh" | head -1)
"$SKILL_DIR/../preflight.sh" || { echo "Preflight failed — fix dependencies first"; exit; }
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

Two modes:

| Mode | Command | Output |
|---|---|---|
| `capture` | `screenshot.sh capture <url> <output.png> [tool]` | Screenshot file |
| `generate` | `screenshot.sh generate <image.png> --prompt "..."` | Path to redesign.png (stdout) |

Both detect tools automatically if not specified. Use env vars `SCREENSHOT_ITERATE_URL` and `SCREENSHOT_GENERATE_SIZE` for overrides.
