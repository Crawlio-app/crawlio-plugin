# Crawlio Plugin for Claude Code

AI-powered website crawling, observation, and analysis for Claude Code.

This plugin connects Claude Code to [Crawlio](https://crawlio.app), a macOS website downloader, giving AI agents the ability to crawl websites, capture browser intelligence, and produce evidence-backed findings.

## Prerequisites

1. **Crawlio** — the macOS app must be installed and running (direct distribution, not App Store)
2. **CrawlioMCP** — the MCP server binary, built from the Crawlio repo
3. **Claude Code** — with plugin support enabled

### Build CrawlioMCP

```bash
cd /path/to/Crawlio-app
swift build -c release --product CrawlioMCP
```

The binary lands at `.build/release/CrawlioMCP`.

## Setup

### 1. Install the Plugin

Clone this repo (or copy the directory) and install it in Claude Code:

```bash
claude plugin install /path/to/crawlio-plugin
```

### 2. Configure the MCP Server Path

Edit `.mcp.json` in this plugin directory and set the path to your `CrawlioMCP` binary:

```json
{
  "mcpServers": {
    "crawlio": {
      "command": "/path/to/.build/release/CrawlioMCP"
    }
  }
}
```

Or set the `CRAWLIO_MCP_PATH` environment variable:

```bash
export CRAWLIO_MCP_PATH=/path/to/.build/release/CrawlioMCP
```

### 3. Start Crawlio

Launch the Crawlio macOS app. It starts a local HTTP control server automatically.

## Skills

### `/crawlio:crawl-site`

Crawl a website with intelligent configuration. Handles site type detection, settings optimization, progress monitoring, and failure retry.

```
/crawlio:crawl-site https://example.com
```

### `/crawlio:observe`

Query the observation log — the timeline of everything Crawlio observed. Filter by host, source, operation type, or time range.

```
/crawlio:observe example.com
```

### `/crawlio:finding`

Create and query curated findings with evidence chains. Record insights that persist across sessions.

```
/crawlio:finding
```

### `/crawlio:audit-site`

Full site audit: crawl, capture enrichment, analyze observations, and produce a findings report with prioritized recommendations.

```
/crawlio:audit-site https://example.com
```

## Agent

### Site Auditor

A custom agent for systematic multi-pass site analysis. Located at `agents/site-auditor.md`.

The site auditor follows a structured protocol:
1. Reconnaissance and configuration
2. Crawl with monitoring
3. Multi-pass analysis (structure, errors, enrichment, synthesis)
4. Evidence-backed findings report

## How It Works

```
Claude Code  ──skill──►  CrawlioMCP  ──HTTP──►  Crawlio App
                         (stdio MCP)             (macOS, 127.0.0.1)
                              │
                              ▼
                         observations.jsonl
                         (per-project timeline)
```

The plugin's skills encode *judgment* — when to use which settings, how to interpret observations, what constitutes a finding. The MCP server handles the *mechanics* — HTTP calls, file reads, protocol bridging.

## Optional: Chrome Extension

For deeper analysis, install the [Crawlio Agent](https://github.com/crawlio/crawlio-agent) Chrome extension. It captures browser-side intelligence (framework detection, network requests, console logs, DOM snapshots) that enriches the observation log.

## Fork This Plugin

This plugin is designed to be forked and customized. See [FORKING.md](FORKING.md) for a guide on creating domain-specific versions.
