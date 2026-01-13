# Security Review - Redmargin

Date: 2026-01-13

## Scope
- Code: Swift app (`AppMain/`, `src/`), WebRenderer JS (`WebRenderer/src/`)
- Docs reviewed: `README.md`, `resources/specs/260110-stage11-security-sandbox.md`, `resources/docs/CHANGELOG.md`
- Threat model: untrusted Markdown file content opened locally; optional remote image loading; no sandbox enabled

## Summary
- Critical: 0
- High: 0
- Medium: 3
- Low: 2

## Context Notes
- The Stage 11 spec explicitly marks full sandbox enablement as blocked pending a custom URL scheme; this is documented but still a security gap in the current code.

## Medium Findings
1) WebView file access scope is broader than the spec intends
- Evidence: `src/Views/MarkdownWebView.swift:132` allows read access to `/` for the WKWebView; navigation is not restricted; sanitizer allows `file:` URLs (`WebRenderer/src/sanitizer.js:48`); relative image resolution does not constrain `..` paths (`WebRenderer/src/index.js:35`).
- Impact: A crafted Markdown file can cause the renderer to read local images outside the document directory. Clicking a `file://` link can navigate to local HTML (outside the sanitizer path). This does not exceed the user’s existing OS permissions but is broader than the spec’s least-privilege goal.
- Mitigation:
  - Restrict `allowingReadAccessTo` to the document’s directory and serve renderer assets via a custom URL scheme handler.
  - Add a `WKNavigationDelegate` policy that blocks `file://` navigations outside an allowlist and routes external links to `NSWorkspace.open`.
  - Canonicalize image paths and enforce they remain within the document directory.

2) App sandbox is disabled in the current build
- Evidence: `Redmargin.entitlements` sets `com.apple.security.app-sandbox` to `false`.
- Impact: The app runs unsandboxed, so any renderer escape or filesystem overreach affects the full user account. The spec notes this is blocked pending a custom URL scheme, but it is still a security gap today.
- Mitigation:
  - Implement a custom URL scheme handler for renderer assets, constrain file access, and enable sandboxing with security-scoped bookmarks.

3) URL scheme allowlist is implicit rather than explicit
- Evidence: `WebRenderer/src/sanitizer.js:57` only blocks `javascript:`/`vbscript:`; `ContentRuleList` blocks `http(s)` (`src/App/ContentRuleList.swift:6`) but does not address other schemes.
- Impact: Non-HTTP schemes (`file:`, `ftp:`, `smb:`) remain possible unless blocked by navigation policy. This is mainly a policy clarity gap today, not a direct exploit.
- Mitigation:
  - Implement explicit scheme allowlists for `href` and `img src`, and enforce them in the sanitizer and navigation delegate.

## Low Findings
1) README and spec claims are slightly stronger than implementation
- Evidence: README claims “JavaScript restricted via WKContentRuleList,” but content rules only block network resources; spec says file access limited to the document directory, but `/` is allowed.
- Impact: Expectations in docs don’t match runtime behavior, which can mislead security posture.
- Mitigation:
  - Align docs with current behavior or implement the documented restrictions.

2) `git` execution relies on PATH resolution
- Evidence: `src/Utilities/ProcessRunner.swift:18` uses `/usr/bin/env` to resolve executables.
- Impact: If PATH were ever influenced, a malicious `git` could execute. This is low-risk for a GUI app but easy to harden.
- Mitigation:
  - Prefer absolute paths (`/usr/bin/git`) with a fallback to PATH if needed.

## Positive Observations
- HTML sanitization is allowlist-based and blocks scripts/events (`WebRenderer/src/sanitizer.js`).
- Remote resources are blocked by default through content rules (`src/App/ContentRuleList.swift`).
- WebView uses a non-persistent data store, reducing stored tracking state (`src/Views/MarkdownWebView.swift:48`).

## Documentation Notes
- `resources/specs/260110-stage11-security-sandbox.md` describes directory-scoped file access and `limitsNavigationsToAppBoundDomains`, which are not currently enforced.
- `README.md` security section should clarify that JS restriction relies on sanitization + navigation policy, not only content rules.
