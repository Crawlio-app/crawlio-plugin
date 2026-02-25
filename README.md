<p align="center">
  <img src="https://raw.githubusercontent.com/Crawlio-app/crawlio/main/.github/banner.svg" alt="Crawlio" width="680">
</p>


# Crawlio AI Skills

Give any AI agent the ability to crawl, observe, and analyze websites using [Crawlio](https://crawlio.app).

5 skills, 1 agent, and an MCP server — packaged as a plugin that follows the [Agent Skills](https://agentskills.io) open standard. The plugin format is just the distribution mechanism. The skills themselves are plain Markdown files that encode domain judgment: when to use which settings, how to interpret observations, what constitutes a finding.

## Prerequisites

1. **Crawlio** — the macOS app must be installed and running ([download](https://crawlio.app))
2. **CrawlioMCP** — the MCP server binary, built from the Crawlio repo
3. **An AI coding tool** with plugin or MCP support (Claude Code, Cursor, Windsurf, etc.)

### Build CrawlioMCP

```bash
cd /path/to/Crawlio-app
swift build -c release --product CrawlioMCP
```

The binary lands at `.build/release/CrawlioMCP`.

## Setup

### 1. Install

**Claude Code** (plugin install):

```bash
claude plugin install /path/to/crawlio-plugin
```

**Other MCP clients** (manual config): Copy the `.mcp.json` contents into your client's MCP configuration. The skills in `skills/` work as standalone Markdown instructions in any agent that supports them.

### 2. Make CrawlioMCP Available in PATH

The MCP config expects `CrawlioMCP` to be in your `$PATH`. After building, symlink or copy it:

```bash
# Option A: symlink into /usr/local/bin
ln -sf /path/to/Crawlio-app/.build/release/CrawlioMCP /usr/local/bin/CrawlioMCP

# Option B: or edit .mcp.json to use the full path
```

If you prefer a full path, edit `.mcp.json` in this directory:

```json
{
  "mcpServers": {
    "crawlio": {
      "command": "/path/to/Crawlio-app/.build/release/CrawlioMCP"
    }
  }
}
```

### 3. Start Crawlio

Launch the Crawlio macOS app. It starts a local HTTP control server automatically.

## Skills

### `/crawlio:crawl-site`

Crawl a website with intelligent configuration. Detects site type, optimizes settings, monitors progress, retries failures, and reports results.

```
/crawlio:crawl-site https://example.com
```

### `/crawlio:extract-and-export`

End-to-end pipeline: crawl a site, extract structured content (clean HTML, markdown, metadata), and export in any of 7 formats.

```
/crawlio:extract-and-export https://docs.stripe.com 5 warc
```

Supported formats: `folder`, `zip`, `singleHTML`, `warc`, `pdf`, `extracted`, `deploy`

### `/crawlio:observe`

Query the observation log — the append-only timeline of everything Crawlio saw during a crawl. Filter by host, source, operation type, or time range.

```
/crawlio:observe example.com
```

### `/crawlio:finding`

Create and query evidence-backed findings. Record insights with observation IDs as evidence that persist across sessions.

```
/crawlio:finding
```

### `/crawlio:audit-site`

Full site audit: crawl, capture enrichment, analyze observations across multiple passes, and produce a findings report with prioritized recommendations.

```
/crawlio:audit-site https://example.com
```

## Agent

### Site Auditor

A custom agent (`agents/site-auditor.md`) for systematic multi-pass site analysis:

1. Reconnaissance and configuration
2. Crawl with monitoring
3. Multi-pass analysis (structure, errors, enrichment, synthesis)
4. Evidence-backed findings report

## How It Works

```
AI Agent  ──skill──►  CrawlioMCP  ──HTTP──►  Crawlio App
                      (stdio MCP)             (macOS, 127.0.0.1)
                           │
                           ▼
                      observations.jsonl
                      (per-project timeline)
```

**Skills** encode *judgment* — when to use which settings, how to interpret observations, what constitutes a finding.

**MCP server** handles *mechanics* — HTTP calls, file reads, protocol bridging.

This separation is what makes the plugin forkable: swap the judgment layer for your domain, keep the same mechanics.

## Optional: Chrome Extension

For deeper analysis, install the [Crawlio Agent](https://github.com/crawlio/crawlio-agent) Chrome extension. It captures browser-side intelligence (framework detection, network requests, console logs, DOM snapshots) that enriches the observation log.

## Fork This Plugin

This plugin is designed to be forked and customized. See [FORKING.md](FORKING.md) for a guide on creating domain-specific versions (SEO auditor, security scanner, competitive analysis, content migration planner).

## License

MIT
