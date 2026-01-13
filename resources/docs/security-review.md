# Security Review - Redmargin

Date: 2026-01-13

## Scope
- Code: Swift app (`AppMain/`, `src/`), WebRenderer JS (`WebRenderer/src/`)
- Docs reviewed: `README.md`, `resources/specs/260110-stage11-security-sandbox.md`, `resources/docs/CHANGELOG.md`
- Threat model: untrusted Markdown file content opened locally; optional remote image loading; no sandbox enabled

## Summary
- Critical: 0
- High: 0
- Medium: 1
- Low: 3

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

## Medium Findings
1) URL scheme allowlist is implicit rather than explicit
- Evidence: `WebRenderer/src/sanitizer.js:57` only blocks `javascript:`/`vbscript:`; `ContentRuleList` blocks `http(s)` (`src/App/ContentRuleList.swift:6`) but does not address other schemes.
- Impact: Non-HTTP schemes (`file:`, `ftp:`, `smb:`) remain possible unless blocked by navigation policy. This weakens the clarity of the “remote loads blocked” guarantee if preferences change.
- Mitigation:
  - Implement explicit scheme allowlists for `href` and `img src`, and enforce them in the sanitizer and navigation delegate.

## Low Findings
1) WebView file access scope is broader than the spec intends
- Evidence: `src/Views/MarkdownWebView.swift:132` allows read access to `/` for the WKWebView; navigation is not restricted; sanitizer allows `file:` URLs (`WebRenderer/src/sanitizer.js:48`); relative image resolution does not constrain `..` paths (`WebRenderer/src/index.js:35`).
- Impact: A crafted Markdown file can cause the renderer to read local images outside the document directory. For direct distribution, this is largely aligned with the app’s full filesystem access posture but is broader than the spec’s least-privilege goal.
- Mitigation:
  - Restrict `allowingReadAccessTo` to the document’s directory and serve renderer assets via a custom URL scheme handler.
  - Add a `WKNavigationDelegate` policy that blocks `file://` navigations outside an allowlist and routes external links to `NSWorkspace.open`.
  - Canonicalize image paths and enforce they remain within the document directory.

2) README and spec claims are slightly stronger than implementation
- Evidence: README claims “JavaScript restricted via WKContentRuleList,” but content rules only block network resources; spec says file access limited to the document directory, but `/` is allowed.
- Impact: Expectations in docs don’t match runtime behavior, which can mislead security posture.
- Mitigation:
  - Align docs with current behavior or implement the documented restrictions.

3) `git` execution relies on PATH resolution
- Evidence: `src/Utilities/ProcessRunner.swift:18` uses `/usr/bin/env` to resolve executables.
- Impact: If PATH were ever influenced, a malicious `git` could execute. This is low-risk for a GUI app but easy to harden.
- Mitigation:
  - Prefer absolute paths (`/usr/bin/git`) with a fallback to PATH if needed.

## Positive Observations
- HTML sanitization is allowlist-based and blocks scripts/events (`WebRenderer/src/sanitizer.js`).
- Remote resources are blocked by default through content rules (`src/App/ContentRuleList.swift`).
- WebView uses a non-persistent data store, reducing stored tracking state (`src/Views/MarkdownWebView.swift:48`).

## Documentation Notes
- `resources/specs/260110-stage11-security-sandbox.md` still describes directory-scoped file access and `limitsNavigationsToAppBoundDomains`, which are not currently enforced.
- `README.md` security section should clarify that JS restriction relies on sanitization + navigation policy, not only content rules.

## Remediation Status (2026-01-13)

| Finding | Status | Notes |
|---------|--------|-------|
| Medium #1: URL scheme allowlist | FIXED | Explicit allowlists in sanitizer: href (http/https/mailto), src (http/https/file) |
| Low #1: File access scope | ACCEPTED | Documented as intentional; navigation policy blocks file:// link clicks |
| Low #2: Docs alignment | FIXED | README and spec updated to reflect actual behavior |
| Low #3: Git PATH resolution | FIXED | ProcessRunner now uses absolute /usr/bin/git with PATH fallback |

Additional hardening implemented:
- Navigation delegate blocks file:// navigations and routes external links to system browser
- Unknown URL schemes blocked in both sanitizer and navigation policy
