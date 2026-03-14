---
description: "Run a Crawlio Sequence — deterministic Swift-native investigation pipeline"
allowed-tools: Read, Bash, Glob, Grep
argument-hint: "<family> <url>"
---

# Crawlio Sequence

Run a deterministic investigation sequence using the native Swift runtime. Sequences execute as state machines — no LLM in the orchestration loop. Local AI inference (ANE) handles reflex tasks; API calls handle synthesis.

## Arguments

`$ARGUMENTS` should be `<family> <url>`.

**Families:** `investigate` `monitor` `extract` `compare` `clone` `test` `compose`

## Execution

1. Read the sequence definition from `sequences/$FAMILY.json`
2. Invoke `CrawlSequenceRunner` via the Crawlio CLI:
   ```bash
   crawlio sequence <family> <url>
   ```
3. The runner manages the state machine:
   - Phases execute as Swift async functions
   - Reflex tasks route to local ANE inference (Tier 2)
   - Synthesis tasks route to Claude API via MCP (Tier 3)
   - Evidence is chained automatically
4. Report results with evidence IDs

## Tiered Cognition

| Tier | Handler | Cost | Latency |
|------|---------|------|---------|
| **1. Deterministic** | Swift parsers (CrawlioCore) | $0.00 | <100ms |
| **2. Local AI** | mentu-ane (Apple Neural Engine / CPU) | $0.00 | ~200ms |
| **3. Cloud AI** | Claude via MCP | $0.01-0.10 | 2-10s |

## Prerequisites

- [Crawlio](https://crawlio.app) macOS app running locally
- For Tier 2: SmolLM2-135M model downloaded (~269MB) via Crawlio Settings
- For Tier 3: Valid API credentials configured
