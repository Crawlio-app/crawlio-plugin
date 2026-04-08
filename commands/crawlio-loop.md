---
description: "Run a Crawlio Loop — AI-orchestrated multi-phase investigation via deep agents"
allowed-tools: Agent, Read, Write, Bash, Glob, Grep
argument-hint: "<family> <url>"
---

# Crawlio Loop

Run an AI-orchestrated investigation loop against a target URL. Loops use Claude Code agents to reason through multi-phase pipelines, producing typed `EvidenceEnvelope<T>` evidence.

## Arguments

`$ARGUMENTS` should be `<family> <url>`.

**Families:** `investigate` `monitor` `extract` `compare` `clone` `test` `compose`

## Execution

1. Read the loop definition from `loops/$FAMILY.json`
2. Generate a runId: `run-<family>-<hostname>`
3. For each phase in the loop:
   - Spawn the phase agent via `Agent()` tool
   - Pass the prior phase's evidenceId in the prompt
   - Capture the output `EVIDENCE_ID=<id>`
4. Run `auditEvidence()` on all produced evidence
5. Report results

## Evidence

All evidence is written to `.crawlio/evidence/runs/<runId>/` as `EvidenceEnvelope<T>` JSON files. Evidence must be produced via `wrapEvidence()` + `writeEvidence()`.

## Families

| Family | Output | Key Phases |
|--------|--------|------------|
| `investigate` | TechBlueprint | crawl, analyze, network, synthesize |
| `monitor` | DiffReport | baseline, recapture, diff |
| `extract` | DesignTokens / AuthFlow / APIMap | crawl, extract, synthesize |
| `compare` | ComparisonReport | crawl-a, crawl-b, compare, synthesize |
| `clone` | CloneBlueprint | crawl, analyze, extract-design, synthesize |
| `test` | TestSuite | crawl, analyze, audit, synthesize |
| `compose` | CompetitiveDossier | 8 phases including audit + extraction |

## Prerequisites

- [crawlio-browser-agent](https://github.com/Crawlio-app/crawlio-browser-agent) Chrome extension + MCP server
- Loop JSON definitions in `loops/` directory
- Phase agents in `.claude/agents/`
