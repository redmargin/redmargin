# Security Review - Redmargin

Date: 2026-01-13

## Scope
- Code: Swift app (`AppMain/`, `src/`), WebRenderer JS (`WebRenderer/src/`)
- Docs reviewed: `README.md`, `resources/specs/260110-stage11-security-sandbox.md`, `resources/docs/CHANGELOG.md`
- Threat model: untrusted Markdown file content opened locally; optional remote image loading; no sandbox enabled

## Summary
- Critical: 0
- High: 0
- Medium: 0
- Low: 0

## Context Notes
- The Stage 11 spec now states app sandboxing is deferred and not required for direct distribution; this review treats that as an intentional product decision rather than a finding.

## Decision Log
- **Sandboxing:** Deferred for direct distribution; aligns with spec and industry practice. Risks managed by sanitization and remote-load blocking.
- **Filesystem access:** Full filesystem access is accepted for this app class; the app is not intended as a hardened, sandboxed viewer.
- **Threat model focus:** Untrusted Markdown should not execute scripts or auto-load remote content by default.

## Risk Acceptance
- Accept full filesystem visibility in the renderer as a product tradeoff for local Markdown workflows.
- Accept non-sandboxed distribution for direct downloads; rely on code signing, notarization, and in-app mitigations.
- Accept that strict least-privilege file access is deferred unless App Store distribution is pursued.

## Open Findings
No open findings based on the current code and updated spec.

## Positive Observations
- HTML sanitization is allowlist-based and blocks scripts/events (`WebRenderer/src/sanitizer.js`).
- URL scheme allowlists are enforced for `href` and `src` (`WebRenderer/src/sanitizer.js`).
- Navigation policy blocks `file://` links and routes external links to the system browser (`src/Views/MarkdownWebView.swift`).
- Remote resources are blocked by default through content rules (`src/App/ContentRuleList.swift`).
- WebView uses a non-persistent data store, reducing stored tracking state (`src/Views/MarkdownWebView.swift:48`).

## Documentation Notes
No documentation mismatches noted after the latest updates.

## Resolved Findings (2026-01-13)

| Finding | Status | Notes |
|---------|--------|-------|
| URL scheme allowlist | FIXED | Explicit allowlists in sanitizer: href (http/https/mailto), src (http/https/file) |
| File access scope | ACCEPTED | Documented as intentional; navigation policy blocks file:// link clicks |
| Docs alignment | FIXED | README and spec updated to reflect actual behavior |
| Git PATH resolution | FIXED | ProcessRunner now uses absolute /usr/bin/git with PATH fallback |

Additional hardening implemented:
- Navigation delegate blocks file:// navigations and routes external links to system browser
- Unknown URL schemes blocked in both sanitizer and navigation policy
