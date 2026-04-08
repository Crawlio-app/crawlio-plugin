---
description: "Explain the Crawlio Intelligence Runtime — loops, sequences, and evidence"
allowed-tools: Read
---

# Crawlio Intelligence Runtime

Two orchestration layers for structured web investigation:

## Crawlio Loops (`/crawlio:crawlio-loop`)
AI-orchestrated multi-phase pipelines via Claude Code agents.
- **Runtime:** crawlio-browser-agent (TypeScript, npm)
- **Cost:** $0.05-0.50 per run | **Speed:** ~2-5 minutes
- **Best for:** Complex reasoning, browser interaction, creative analysis

## Crawlio Sequences (`/crawlio:crawlio-seq`)
Deterministic Swift state machines running natively in the Crawlio macOS app.
- **Runtime:** Crawlio-app (Swift 6, macOS 15+)
- **Cost:** $0.00-0.01 per run | **Speed:** ~5-30 seconds
- **Best for:** High-volume crawl+parse, monitoring, deterministic extraction

## The 7 Families

| Family | What It Produces |
|--------|-----------------|
| **investigate** | Full-depth TechBlueprint of a site's stack |
| **monitor** | DiffReport showing what changed between visits |
| **extract** | Design tokens, auth flows, or API maps |
| **compare** | Side-by-side analysis of two websites |
| **clone** | Blueprint for reproducing a site's design system |
| **test** | Security / accessibility / performance test suite |
| **compose** | Comprehensive competitive dossier |

## Evidence

Both layers produce interchangeable `EvidenceEnvelope<T>` with typed payloads, gap detection, quality derivation, and provenance tracking. A Loop can consume evidence from a Sequence and vice versa.
