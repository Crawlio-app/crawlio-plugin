---
name: design-system
description: Use this skill when the user asks to "extract design tokens", "clone the look", "get the color palette", or "rebuild the UI" of a live web page. Produces a design-tokens JSON of colors, typography, spacing, and breakpoints from computed styles.
license: MIT
version: 2.0.0
allowed-tools: mcp__crawlio__*
---

# design-system

Extract a design-tokens JSON (colors, typography, spacing, breakpoints) from a live web page. Routes through the `crawlio-agent-headless` pillar of `@crawlio/mcp`, which invokes `skill_extract_design_system` via the session-based RE API.

The output is structured enough to drop directly into a Tailwind config, a CSS custom-property sheet, or a Figma tokens plugin.

## When to Use

- User wants to "clone the look" of a site they are rebuilding (their own legacy site, a design they are migrating, or a reference they have permission to reproduce)
- User wants to audit their own site's color palette for consistency — e.g. "how many shades of blue are we actually shipping?"
- User is preparing a migration plan and needs a concrete token inventory before touching CSS

Do NOT use this skill to wholesale clone a site you do not have authorization to reproduce. Design-token extraction is fine for inspiration and for sites you own; direct visual cloning of someone else's commercial product without permission is not.

## Headless RE Session API

The headless pillar uses a **session-based** API. You create a session first, then run skills within it.

**Important server/tool names:**
- Server: `"crawlio-agent-headless"` (NOT `"headless"` — that alias does not resolve)
- Session tool: `"skill_session_create"` → then `"skill_run"` with `{ name: "..." }`
- Individual skill names like `"skill_extract_design_system"` are NOT top-level tools — they are arguments to `skill_run`

## Protocol: Session > Sample > Review > Emit

### 0. Create an RE session

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_session_create",
  args: { url: "https://target.example.com", maxCalls: 30 }
})
```

### 1. Sample

Run the extraction skill:

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_extract_design_system" }
})
```

The underlying skill walks the live DOM, reads `getComputedStyle` on a sampled set of elements, and collects raw style values.

Read `status` first:
- `complete` — full token set extracted
- `partial` — some categories (e.g. breakpoints) could not be inferred from a single viewport sample
- `unavailable` — the `browser` tier is not provisioned on the headless pillar

### 2. Review the token set

The response includes a `design_tokens` artifact containing:

- **`colors`** — deduped palette, clustered by hue/lightness. Expect the primary brand color, a handful of neutrals, and semantic colors (success/error/warning).
- **`typography`** — `{ fontFamilies, fontSizes, fontWeights, lineHeights, letterSpacings }`. Font families are deduped across all text nodes.
- **`spacing`** — ordered list of unique margin/padding/gap values in px.
- **`breakpoints`** — inferred from `@media` rules in loaded stylesheets (may be incomplete from a single viewport; the skill notes this as a gap).
- **`radii`** — border-radius values in use.
- **`shadows`** — box-shadow declarations (often a signal of depth-system design).

Sanity-check before emitting:
- Is the primary color stable across samples, or are there near-duplicates that should be merged manually?
- Do spacing values form a recognizable scale (4/8/16/24…) or is the page using ad-hoc pixels? Report the scale behavior to the user.
- Are there more than ~8 unique font sizes? That usually indicates a design system with no enforced typographic scale — worth calling out.

### 3. Emit

Produce the token set in the output format the user asked for. Common formats:

**Tailwind config fragment:**
```js
module.exports = {
  theme: {
    extend: {
      colors: { /* palette from tokens */ },
      fontFamily: { /* families */ },
      spacing: { /* scale */ },
      borderRadius: { /* radii */ },
    }
  }
}
```

**CSS custom properties:**
```css
:root {
  --color-primary: #1D4ED8;
  --font-sans: "Inter", system-ui;
  --space-1: 4px;
  /* ... */
}
```

**Design Tokens Community Group (DTCG) JSON:**
```json
{
  "color": { "primary": { "$value": "#1D4ED8", "$type": "color" } },
  "font": { "sans": { "$value": "Inter", "$type": "fontFamily" } }
}
```

Ask the user which format they want before dumping. Default to DTCG JSON when unspecified — it's portable across tools.

## Optional follow-up: clone the page

If the user wants more than tokens — a full React + Tailwind scaffold of the page — chain into `skill_clone_site` within the same session:

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_clone_site" }
})
```

This is a heavy operation (estimatedCalls: 28) and only makes sense when the user has explicit authorization to reproduce the page. Confirm before invoking.

## Anti-Patterns

**Do not** call `tool: "skill_extract_design_system"` directly — that tool name does not exist on the aggregator. Use `skill_run({ name: "skill_extract_design_system" })`.

**Do not** use `server: "headless"` or `server: "app"`. The correct names are `"crawlio-agent-headless"` and `"crawlio"`.

**Do not** emit tokens verbatim without clustering. Raw `getComputedStyle` output on a complex page will yield 50+ colors and 20+ font sizes; the skill already clusters them, but if you bypass the skill and hand-roll the extraction you'll ship noise as a design system.

**Do not** claim breakpoint completeness from a single viewport. The skill will flag `breakpoints` as a partial gap when the page does not expose its full `@media` rule set. Report that honestly.

**Do not** use this skill to clone commercial sites wholesale. Tokens for inspiration is fair; pixel-perfect reproduction of someone else's product is not.

## Example Workflow

```
// 0. Create RE session
const session = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_session_create",
  args: { url: "https://our-site.example.com", maxCalls: 30 }
})

// 1. Extract tokens
const tokens = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_extract_design_system" }
})

// 2. Audit
// Check token.artifacts for color count, font size proliferation, etc.

// 3. Emit as Tailwind config
// → hand the user a tailwind.config.js fragment

// 4. Optionally clone (with authorization)
const clone = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_clone_site" }
})
```
