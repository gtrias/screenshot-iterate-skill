# Screenshot-Iterate — Basic Loop Example

Complete walkthrough showing a full iteration cycle on a landing page hero section.

## Setup

**Preflight check:**

```bash
$ scripts/preflight.sh
{
  "openai_api_key": true,
  "screenshot_tool": "playwright",
  "dev_server_url": "http://localhost:5173",
  "impeccable": true,
  "max_iterations": 5,
  "errors": []
}
```

All dependencies OK. Ready to iterate.

---

## Iteration 1: Spacing and layout

**Target:** `/p/photographer-slug` (landing page hero)

### Capture baseline

```bash
scripts/screenshot.sh capture "http://localhost:5173/p/photographer-slug" \
  /tmp/screenshot-iterate/session-4829/baseline.png
```

Read `baseline.png` → current state shows cramped hero section with inconsistent spacing.

### Generate redesign

```bash
scripts/screenshot.sh generate /tmp/screenshot-iterate/session-4829/baseline.png \
  --prompt "Redesign this landing page hero. Increase whitespace between heading and CTA button. Add breathing room around the hero image. Use consistent vertical rhythm with 8px grid spacing. Improve visual hierarchy: larger headline, clearer subheading." \
  --model gpt-image-2
```

Output: `/tmp/screenshot-iterate/session-4829/baseline-redesign.png`

### Critique

Run `$impeccable critique` with both images as reference.

**Actionable items extracted:**
- Hero padding: `py-16` → `py-24`
- Heading-subheading gap: `mb-2` → `mb-4`
- Subheading-CTA gap: `mb-4` → `mb-8`
- Container max-width: add `max-w-4xl mx-auto`

### Implement spacing changes

Modify hero component with only spacing changes. No other modifications.

### Re-screenshot and compare

```bash
scripts/screenshot.sh capture "http://localhost:5173/p/photographer-slug" \
  /tmp/screenshot-iterate/session-4829/iter-1.png
```

**Result:** Critique score improved from 58 → 72. Spacing issues resolved. ✅

---

## Iteration 2: Typography hierarchy

### Capture new baseline (iteration 1 result)

Use `iter-1.png` as new baseline.

### Generate redesign with typography focus

```bash
scripts/screenshot.sh generate /tmp/screenshot-iterate/session-4829/iter-1.png \
  --prompt "Improve typography hierarchy. Make the headline bolder and larger (text-5xl → text-6xl). Subheading should use a lighter weight and slightly smaller size for clear contrast. Ensure body text stays at 16px minimum." \
  --model gpt-image-2
```

### Critique

**Actionable items extracted:**
- Heading: `text-4xl font-semibold` → `text-6xl font-bold`
- Subheading: `text-lg font-normal` → `text-base font-light text-muted-foreground`

### Implement typography changes

Apply only typography changes to hero component.

### Re-screenshot and compare

**Result:** Critique score improved from 72 → 84. Typography hierarchy clear. ✅

---

## Iteration 3: Color polish

### Capture new baseline (iteration 2 result)

Use `iter-2.png` as new baseline.

### Generate redesign with color focus

```bash
scripts/screenshot.sh generate /tmp/screenshot-iterate/session-4829/iter-2.png \
  --prompt "Refine color palette. CTA button should use brand accent color with subtle hover state. Hero background should have a very subtle warm tint instead of pure white. Text colors should maintain good contrast." \
  --model gpt-image-2
```

### Critique

**Actionable items extracted:**
- CTA: `bg-primary` → `bg-accent hover:bg-accent/90 transition-colors`
- Hero bg: `bg-white` → `bg-[#faf9f7]` (warm tint)
- Muted text: ensure contrast ratio > 4.5:1

### Implement color changes

Apply only color changes.

### Re-screenshot and compare

**Result:** Critique score improved from 84 → 86 (+2). Diminishing returns detected. ⚠️

---

## Loop completion (stall detected: only +2 after iteration 3)

```
Loop completed (3/5 iterations)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Screen: Photographer landing page hero
Scores: 58 → 86 (+28)
Categories resolved: spacing ✓ | typography ✓ | color ⚠️ (diminishing returns)
Commit? [y/n] "chore(ui): redesign photographer landing hero - 3 iterations, score 58→86"
```

**Summary:** 3 iterations, 28-point improvement. Spacing and typography delivered the bulk of gains. Color polish was minimal — likely sufficient as-is.
