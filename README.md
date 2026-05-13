# Screenshot-Iterate Skill

[![skills.sh](https://skills.sh/b/gtrias/screenshot-iterate-skill)](https://skills.sh/gtrias/screenshot-iterate-skill)

Screenshot-driven design iteration loop for AI agents. Capture a screen, generate an improved design with GPT Image 2, critique with impeccable, implement changes, repeat.

## Install

```bash
npx skills add gtrias/screenshot-iterate-skill
```

## How it works

1. **Preflight** — validates dependencies (OpenAI API key, screenshot tool, impeccable skill)
2. **Capture** — takes a screenshot of the target screen using Playwright or pinchtab
3. **Generate** — GPT Image 2 produces a redesigned version based on improvement prompts
4. **Critique** — `$impeccable critique` extracts actionable code changes
5. **Implement** — applies one category of changes at a time (spacing, typography, color, layout, polish)
6. **Compare** — re-screenshots and loops until max iterations or no improvement

## Dependencies

- `OPENAI_API_KEY` environment variable set
- A screenshot tool: Playwright or pinchtab running on `localhost:9867`
- Dev server running (default: `localhost:3000`, override with `SCREENSHOT_ITERATE_URL`)
- [impeccable](https://github.com/anthropics/skills) skill installed

## Configuration

| Env var | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | — | OpenAI API key (required) |
| `MAX_ITERATIONS` | 5 | Maximum iterations per loop |
| `SCREENSHOT_ITERATE_URL` | `http://localhost:3000` | Dev server URL |
| `SCREENSHOT_GENERATE_SIZE` | `1536x1024` | Output image size for GPT Image 2 |

## Usage

Specify a target screen to improve. The agent will run the iteration loop automatically.

```
/screenshot-iterate /p/photographer-slug
/screenshot-iterate src/components/Header.tsx
/screenshot-iterate "the pricing page"
```

## Concepts Mode (3-option pick)

On the first iteration the skill generates 3 radically different design directions in parallel and lets you pick one (or refine, or regenerate) before any code changes happen. Subsequent iterations use single-shot generation within the chosen direction.

### Example interaction

```
Option 1 — Bold & expressive
  Strong type, accent colors, dense hierarchy.

Option 2 — Minimal & restrained
  Generous whitespace, neutral palette, quiet typography.

Option 3 — Structured & editorial
  Grid-driven sections, content-first, clear visual rhythm.

Reply: 1 | 2 | 3 | refine N: <tweak> | regenerate
```

### `CONCEPTS_MODE`

| Value | Behavior |
|---|---|
| `first` (default) | 3 options on iteration 1, single-shot after |
| `always` | 3 options every iteration (higher cost) |
| `never` | Disable; reproduces pre-concepts single-shot behavior end-to-end |

### Session layout

```
.screenshot-iterate/
├── INDEX.md                                  # session log
└── sessions/
    └── 2026-05-13_14-30-22-pricing-page/
        ├── meta.json                         # target, chosen, scores
        ├── baseline.png
        ├── concepts/
        │   ├── round-1/
        │   │   ├── option-1.png
        │   │   ├── option-2.png
        │   │   ├── option-3.png
        │   │   └── options.json
        │   ├── round-2/                      # if regenerated
        │   └── chosen.png
        └── iterations/
            └── iter-N-<category>.png
```

### Storybook

If a Storybook setup is detected (`.storybook/` dir or `storybook` in package.json), the 3 current concepts are also written as a story at `src/stories/ScreenshotIterateConcepts.stories.tsx` so you can browse them in Storybook UI.

### Backwards compatibility

Setting `CONCEPTS_MODE=never` reproduces the pre-concepts single-shot behavior end-to-end.

## Scripts

| Script | Description |
|---|---|
| `scripts/preflight.sh` | Dependency validation (JSON output) |
| `scripts/screenshot.sh capture <url> <output.png>` | Screenshot via Playwright or pinchtab |
| `scripts/screenshot.sh generate <image.png> --prompt "..."` | GPT Image 2 generation |

## Prompt templates

Built-in templates for common iteration categories:

- **Spacing** — layout rhythm, whitespace, 8px grid consistency
- **Typography** — heading hierarchy, body readability, line length
- **Color** — palette refinement, contrast ratios, subtle tints
- **Layout** — alignment, grid structure, visual flow
- **Polish** — micro-details, border radius, transitions, pixel-perfect alignment

## License

Apache 2.0
