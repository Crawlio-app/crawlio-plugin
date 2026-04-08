---
name: crawlio-seq
description: Manage the Crawlio Intelligence Runtime — create and run Crawlio Loops (AI-orchestrated deep agents) and Crawlio Sequences (deterministic Swift state machines) for structured web investigation.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Agent
argument-hint: "[loop|seq] <family>"
---

# Crawlio Intelligence Runtime

Create and manage investigation pipelines across two orchestration layers:

- **Crawlio Loops** — AI-orchestrated via Claude Code agents (deep, flexible, expensive)
- **Crawlio Sequences** — Deterministic Swift state machines (fast, free, reliable)

## Usage

- `/crawlio:crawlio-seq loop <family>` — Create a Crawlio Loop definition
- `/crawlio:crawlio-seq seq <family>` — Create a Crawlio Sequence definition
- `/crawlio:crawlio-seq --info` — Show current loops, sequences, and evidence

## Families

investigate, monitor, extract, compare, clone, test, compose

## Evidence

Both layers produce `EvidenceEnvelope<T>` with typed payloads, provenance, gaps, and quality. Evidence is interchangeable between layers.
