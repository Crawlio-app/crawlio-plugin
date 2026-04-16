---
name: decompile-spa
description: Use this skill when the user asks to "decompile", "unbundle", "reverse engineer", or "understand the architecture of" a single-page application. Produces a module graph, client route table, and state-management framework detection by routing through the crawlio-agent-headless reverse-engineering pillar.
license: MIT
version: 2.0.0
allowed-tools: mcp__crawlio__*
---

# decompile-spa

Reverse-engineer a single-page application: unbundle its JavaScript, reconstruct the module graph, map its client-side routes, and detect its state-management framework.

This skill composes three underlying crawlio-agent-headless skills via the `@crawlio/mcp` aggregator. The aggregator dispatches the calls through the `crawlio-agent-headless` pillar, which provides the grep/interceptor/browser tiers required for static and dynamic analysis.

## When to Use

- User wants to "understand how this app is built" without reading minified source by hand
- User asks to "find the routes" or "map the state management" of a live SPA
- Preparing for a design-system extraction or a competitive teardown — this skill produces the structural substrate that later skills depend on

Do NOT use this skill on sites you do not own or do not have authorization to analyze. Reverse engineering is scoped to legitimate research, competitive teardowns you are authorized to run, and your own applications.

## Headless RE Session API

The headless pillar uses a **session-based** API. You do not call individual skills directly — you create a session, then run skills within it. The session tracks budget, artifacts, and gaps across skill invocations.

### 0. Create an RE session (required first step)

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_session_create",
  args: { url: "https://target.example.com", maxCalls: 50 }
})
```

Returns a `sessionId` and budget object. All subsequent `skill_run` calls operate within this session until it expires or is exhausted.

## Core Protocol: Unbundle > Map > Classify

### 1. Unbundle the bundle

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_decompile_spa" }
})
```

The response contains `artifacts` with `decompiled_module` records (one per main bundle, up to 3) and a `route_map` record containing exports/imports/routes structural search output. The `gaps` field will flag `dynamic_imports` if the interceptor tier is unavailable and `source_maps` as a second-order gap.

Read `status` first:
- `complete` — module graph successfully extracted, proceed
- `partial` — some bundles unbundled but gaps are blocking, note and proceed with reduced confidence
- `unavailable` — the grep tier is not provisioned; stop and surface the gap to the user

### 2. Map client routes

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_map_client_routes" }
})
```

This builds on the module graph produced in step 1 (artifacts carry across the session). The response includes a `route_map` artifact — a list of `{ path, component, guards }` tuples — and a detected router framework (`react-router`, `vue-router`, `next/router`, `svelte-kit`, etc.).

### 3. Analyze state management

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_analyze_state_management" }
})
```

The response identifies the state-management library (Redux, Zustand, Pinia, Vuex, MobX, Jotai, Recoil, etc.), rough store shape, and any derived selectors it can find.

### 4. Check what to do next (optional)

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_suggest",
  args: {}
})
```

Returns recommended next skills based on the artifacts and gaps accumulated in the session so far.

## Normalize

Before emitting findings, normalize the three results into a single teardown record:

- **Architecture**: `{ bundler, framework, router, stateManager }`
- **Routes**: list of `{ path, component }` from step 2
- **Modules**: top-level module names from step 1's module graph
- **Gaps**: merged list from all three steps — be honest about what was not recoverable

## Persist as a finding

After the three-step teardown, record a finding so the result survives across sessions:

```
mcp__crawlio__call({
  server: "crawlio",
  tool: "create_finding",
  args: {
    title: "<target> — SPA teardown",
    url: "https://target.example.com",
    evidence: [],
    synthesis: "<one-paragraph teardown summary>",
    confidence: "high" | "medium" | "low",
    category: "reverse-engineering"
  }
})
```

## Anti-Patterns

**Do not** call `tool: "skill_decompile_spa"` directly — that tool name does not exist on the aggregator. Always go through `skill_session_create` → `skill_run({ name: "..." })`.

**Do not** use `server: "headless"` — that alias does not resolve. The correct server name is `"crawlio-agent-headless"`.

**Do not** improvise a decompilation by hand-grepping the minified source. The `skill_decompile_spa` skill handles source-map fallback, webpack/vite/rollup unbundling, and structural search in one call.

**Do not** run this skill on an arbitrary third-party site without authorization.

**Do not** skip step 2 or 3 and claim "architecture analysis". A module graph alone is not architecture. Routes and state shape are what make the teardown useful.

## Example Workflow

```
// 0. Create RE session
const session = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_session_create",
  args: { url: "https://app.example.com", maxCalls: 50 }
})
// → { sessionId: "re_abc123", budget: { maxCalls: 50, callsUsed: 0 } }

// 1. Unbundle
const decomp = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_decompile_spa" }
})

// 2. Map routes
const routes = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_map_client_routes" }
})

// 3. Classify state
const state = mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_analyze_state_management" }
})

// 4. Record a finding
mcp__crawlio__call({
  server: "crawlio",
  tool: "create_finding",
  args: {
    title: "example.com — SPA teardown",
    url: "https://app.example.com",
    evidence: [],
    synthesis: "React 18 SPA, Vite bundler, React Router v6 with 23 routes, Redux Toolkit store.",
    confidence: "high",
    category: "reverse-engineering"
  }
})
```
