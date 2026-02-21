# Forking the Crawlio Plugin

This plugin is designed as a "maximally forkable" starting point. The MCP server handles the mechanics (crawling, storing, querying). The skills encode the *judgment* — what to look for, how to interpret results, when to create findings. Fork the skills to encode *your* domain expertise.

## How to Fork

1. Fork this repo
2. Customize skills for your domain
3. Add domain-specific finding categories
4. Adjust the audit checklist
5. Publish your fork as a standalone plugin

## What to Customize

### Skills

Skills are Markdown files that guide Claude's behavior. Edit them to focus on your domain:

| File | What to Change |
|------|---------------|
| `skills/crawl-site/SKILL.md` | Settings presets, site type detection logic |
| `skills/observe/SKILL.md` | Which observations matter for your use case |
| `skills/finding/SKILL.md` | Finding categories, quality criteria |
| `skills/audit-site/SKILL.md` | Audit checklist, report structure |

### Agent

The agent at `agents/site-auditor.md` defines a multi-pass analysis protocol. Customize it for your domain's analysis workflow.

## Fork Examples

### SEO Auditor

Focus on search engine optimization:

**`skills/audit-site/SKILL.md`** changes:
- Check meta tags (title, description, canonical) on every page
- Analyze heading hierarchy (H1-H6)
- Flag missing alt attributes on images
- Check for structured data (JSON-LD, OpenGraph)
- Identify thin content pages
- Map internal linking structure

**Finding categories**: Missing meta descriptions, duplicate titles, broken canonical tags, missing structured data, thin content, orphaned pages

**Example finding**:
```
create_finding({
  title: "12 pages missing meta descriptions",
  url: "https://example.com",
  evidence: ["obs_xxx"],
  synthesis: "12 out of 142 pages have no meta description tag. Pages include /about, /team, /careers, and 9 blog posts from 2024. Missing descriptions reduce click-through rates from search results."
})
```

### Security Scanner

Focus on web security issues:

**`skills/audit-site/SKILL.md`** changes:
- Check HTTPS enforcement and mixed content
- Review security headers (CSP, HSTS, X-Frame-Options)
- Identify exposed API endpoints
- Flag sensitive files (`.env`, `.git/`, `wp-config.php`)
- Check for information disclosure in error pages
- Analyze third-party script origins

**Finding categories**: Mixed content, missing security headers, exposed endpoints, information disclosure, unsafe third-party scripts

### Competitive Analysis

Focus on comparing competitor sites:

**`skills/crawl-site/SKILL.md`** changes:
- Settings optimized for quick framework detection (shallow crawl)
- Multi-site crawl workflow (crawl several competitors)

**`skills/audit-site/SKILL.md`** changes:
- Framework comparison across competitors
- CDN and hosting analysis
- Third-party service comparison (analytics, chat, payments)
- Content volume comparison
- Technology stack evolution tracking

### Content Migration Planner

Focus on site migration planning:

**`skills/audit-site/SKILL.md`** changes:
- Map all URLs and their content types
- Identify URL patterns and path structures
- Track redirect chains (301/302)
- Flag orphaned content
- Generate URL mapping table (old → new)
- Estimate content volume per section

## Adding New Skills

Create a new directory under `skills/`:

```
skills/
└── your-new-skill/
    └── SKILL.md
```

The skill becomes available as `/crawlio:your-new-skill`.

### Skill Structure

```markdown
# skill-name

One-line description of what this skill does.

## When to Use

Describe when to invoke this skill.

## Workflow

Step-by-step instructions for Claude to follow.
Include MCP tool calls with example parameters.

## Tips

Practical advice for best results.
```

## Adding New Agents

Create a new Markdown file under `agents/`:

```
agents/
└── your-agent.md
```

Agents define persistent behavior patterns. They describe:
- What tools the agent has access to
- A protocol to follow
- Quality standards for output
- Behavioral guidelines

## Publishing Your Fork

1. Update `plugin.json` with your fork's name and description
2. Update `README.md` with your domain-specific setup instructions
3. Push to your own GitHub repo
4. Users install with: `claude plugin install github:you/your-fork`
