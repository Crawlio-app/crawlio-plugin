---
name: extract-secrets
description: Use this skill when the user asks to "find hardcoded secrets", "scan for API keys", or "audit credentials" in a web application they own or are authorized to test. Scans decompiled JavaScript and classifies findings as confirmed, potential, or false positive.
license: MIT
version: 2.0.0
allowed-tools: mcp__crawlio__*
---

# extract-secrets

Scan a web application's decompiled JavaScript for hardcoded API keys, tokens, credentials, and endpoint URLs. Routes through the `crawlio-agent-headless` pillar of `@crawlio/mcp`, which invokes `skill_extract_secrets` via the session-based RE API.

## Authorization — read this first

This skill is ONLY for:

1. **Sites you own** — your own production or staging apps.
2. **Authorized pentests** — engagements where you have explicit written authorization to probe the target.
3. **Your own JavaScript bundles** — internal security review before shipping.

If the user asks you to run this against a third-party site without proof of authorization, refuse and explain why. Unauthorized secret scanning is unethical and in many jurisdictions illegal. Ask the user to confirm authorization in writing before proceeding. When in doubt, do not run.

## When to Use

- Pre-release audit of your own frontend bundle
- Authorized penetration-testing engagement where credential exposure is in scope
- Confirming a bug-bounty submission on a program that covers credential disclosure

## Headless RE Session API

The headless pillar uses a **session-based** API. You create a session first, then run skills within it.

**Important server/tool names:**
- Server: `"crawlio-agent-headless"` (NOT `"headless"` — that alias does not resolve)
- Session tool: `"skill_session_create"` → then `"skill_run"` with `{ name: "..." }`
- Individual skill names like `"skill_extract_secrets"` are NOT top-level tools — they are arguments to `skill_run`

## Protocol: Session > Scan > Classify > Report

### 0. Create an RE session

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_session_create",
  args: { url: "https://app.you-own.com", maxCalls: 30 }
})
```

### 1. Scan

If the target hasn't been decompiled yet in this session, run `skill_decompile_spa` first — `skill_extract_secrets` works best on already-unbundled code:

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_decompile_spa" }
})
```

Then run the secrets scan:

```
mcp__crawlio__call({
  server: "crawlio-agent-headless",
  tool: "skill_run",
  args: { name: "skill_extract_secrets" }
})
```

If `decompiled_module` artifacts already exist in the session (from a prior `decompile-spa` invocation), the secrets skill reuses them automatically.

### 2. Classify

The response contains findings pre-classified into three buckets:

- **`confirmed`** — high-entropy strings (32+ char hex or base64) in assignment position, not inside a comment. Highest priority.
- **`potential`** — matches the identifier pattern but entropy is lower or context is ambiguous. Needs human review.
- **`false_positive`** — in a comment, example block, or placeholder like `xxx`/`YOUR_KEY_HERE`. Discard.

Do NOT treat `potential` as `confirmed` without manual validation. Show them to the user separately.

### 3. Report

Produce a structured report:

```
## Confirmed exposures (urgent)
- <redacted value snippet> — <file:line> — <rationale>

## Potential exposures (review needed)
- <redacted value snippet> — <file:line> — <what makes it ambiguous>

## Scanned corpus
- Bundles: <N> JS files totalling <bytes>
- Tools used: mgrep_structural_search, mgrep_text_search, mgrep_yara_scan (if available)
```

**Never include the full raw secret in the report body.** Redact to the first and last 4 characters (`sk_live_abc1…xyz4`) so the evidence remains useful without re-leaking the credential downstream.

## Follow-up actions

For each confirmed exposure:

1. **Rotate the credential immediately.** This is the first thing to communicate to the user — nothing else is as urgent.
2. Open a finding via the `crawlio` server:
   ```
   mcp__crawlio__call({
     server: "crawlio",
     tool: "create_finding",
     args: {
       title: "Hardcoded <credential type> in production bundle",
       url: "https://app.you-own.com",
       evidence: [],
       synthesis: "Found <redacted> in <file>. Source: <context>. Action: rotate and move to env vars.",
       confidence: "high",
       category: "security"
     }
   })
   ```
3. Suggest a fix: move the value to an environment variable, a backend proxy endpoint, or a signed short-lived token depending on the use case.

## Anti-Patterns

**Do not** call `tool: "skill_extract_secrets"` directly — that tool name does not exist on the aggregator. Use `skill_run({ name: "skill_extract_secrets" })`.

**Do not** use `server: "headless"` or `server: "app"`. The correct names are `"crawlio-agent-headless"` and `"crawlio"`.

**Do not** run this skill on a site without authorization. No exceptions.

**Do not** dump raw secrets into the chat transcript, logs, or finding bodies. Redact every value before it leaves the scan tool.

**Do not** close out a confirmed finding without telling the user to rotate the credential first. Rotation is the mitigation; the code change is the cleanup after.

**Do not** treat `potential` findings as actionable without manual review. False positives are common in bundler output — especially inside comments and webpack runtime glue.

## Gaps to watch for

The underlying skill may return `gaps` for:

- **Dynamic imports** — chunks loaded via `import()` at runtime are only visible if the `interceptor` tier is available. Without it, lazy-loaded secrets stay hidden.
- **Source maps** — when source maps are present, fidelity is much higher. When they're stripped, the scan operates on minified output and classification gets noisier.
- **YARA availability** — if `mgrep_yara_scan` is not provisioned, signature-based detection of known vendors (AWS, GCP, Stripe, etc.) is skipped.

Call these out explicitly in the report so the user knows what the scan did not cover.
