# Security Review - Redmargin

## Latest Review: 2026-01-26

**Scope**: Full codebase including SSH remote features

**Files reviewed**: `src/Views/MarkdownWebView.swift`, `src/Core/Utilities/ProcessRunner.swift`, `src/Core/Remote/Client/SSHConnection.swift`, `src/Core/Remote/Client/ServerDeployer.swift`, `Server/FileOperations.swift`, `Server/RPCHandler.swift`, `WebRenderer/src/sanitizer.js`, `WebRenderer/src/index.js`, `RedMargin.entitlements`

### Summary

- Critical: 0
- High: 1
- Medium: 2

---

## Open Findings

### [HIGH] WKWebView filesystem access overly permissive

**Location**: `src/Views/MarkdownWebView.swift:186-187`

**Issue**: The WKWebView grants read access to the entire filesystem:

```swift
let accessURL = URL(fileURLWithPath: "/")
webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)
```

While `allowFileAccessFromFileURLs` is disabled, this broad access combined with the sanitizer's `file://` scheme allowlist for `<img src>` means malicious Markdown could probe local file paths via image load timing/errors.

**Impact**: File existence disclosure via side channels. No data exfiltration possible (content rules block remote requests).

**Action Items**:

- [ ] Restrict `allowingReadAccessTo:` to document directory and bundle resources only
- [ ] Calculate common ancestor of renderer path and document path for access URL
- [ ] Test that relative image paths still resolve after the change

---

### [MEDIUM] Remote server binary deployed without signature verification

**Location**: `src/Core/Remote/Client/ServerDeployer.swift:162-186`

**Issue**: Server binary verified only by MD5 hash comparison. No code signature verification before deployment. If app bundle is tampered post-notarization, malicious binary could be deployed.

**Impact**: Potential RCE on remote host if app bundle compromised.

**Action Items**:

- [ ] Evaluate adding `codesign --verify` check on bundled binary before upload
- [ ] Consider embedding expected binary hash in app code for verification
- [ ] Document that hardened runtime protects bundle integrity (defense-in-depth)

---

### [MEDIUM] Server-side path traversal not explicitly prevented

**Location**: `Server/FileOperations.swift:47-67`, `Server/RPCHandler.swift`

**Issue**: `readFile`/`writeFile` accept paths from RPC without canonicalization or traversal checks. However, SSH connection already grants equivalent shell access.

**Impact**: No additional privilege gained - SSH user already has full access.

**Action Items**:

- [ ] Document that server trusts SSH-authenticated client (by design)
- [ ] Consider optional server-side directory restriction for defense-in-depth (low priority)
- [ ] No code change required - accept as design decision

---

## Positive Observations

### WKWebView Security (MarkdownWebView.swift)

- [x] `allowFileAccessFromFileURLs` disabled (line 65)
- [x] Non-persistent data store prevents session persistence (line 66)
- [x] Content Rule Lists block remote resources by default (lines 101-114)
- [x] Navigation delegate blocks cross-file navigation and unknown schemes (lines 350-396)
- [x] External links open in system browser, not WebView (line 354)
- [x] `allowsLinkPreview` disabled (line 90)
- [x] Fragment escaping for safe JavaScript execution (lines 372-374)

### HTML Sanitization (sanitizer.js)

- [x] Allowlist-based tag filtering with explicit dangerous tag removal (lines 149-158)
- [x] URL scheme allowlist (not blocklist) for href and src (lines 49, 52)
- [x] `javascript:` blocked implicitly by allowlist approach
- [x] Data URLs restricted to safe image MIME types, SVG excluded (lines 115-117)
- [x] Event handlers (`on*`) removed (lines 206-209)
- [x] Only checkbox inputs allowed, other input types stripped (lines 173-179)

### Process Execution (ProcessRunner.swift)

- [x] Known paths mapping for security-critical executables like `git` (lines 15-17)
- [x] Arguments passed as array, not shell string (line 39)
- [x] Timeout support prevents hanging processes (lines 134-138)

### SSH Connection (SSHConnection.swift)

- [x] Hardcoded `/usr/bin/ssh` path (line 309)
- [x] BatchMode=yes prevents interactive prompts (line 316)
- [x] Connection and operation timeouts (lines 167-189, 391)
- [x] Actor-based concurrency for thread safety

### Entitlements (RedMargin.entitlements)

- [x] No dangerous entitlements (disable-library-validation, allow-dyld-environment-variables, etc.)
- [x] Security-scoped bookmarks for persistent file access

---

## Risk Acceptance

- **Filesystem visibility**: Accept full filesystem access in renderer as product tradeoff for local Markdown workflows
- **Non-sandboxed distribution**: Accept for direct downloads; rely on code signing, notarization, and in-app mitigations
- **SSH trust model**: Accept that authenticated SSH connection implies full trust of connected host

---

## Resolved Findings

### From 2026-01-13 Review

| Finding | Status | Notes |
| --- | --- | --- |
| URL scheme allowlist | FIXED | Explicit allowlists in sanitizer: href (http/https/mailto), src (http/https/file) |
| File access scope | ACCEPTED | Documented as intentional; navigation policy blocks file:// link clicks |
| Docs alignment | FIXED | README and spec updated to reflect actual behavior |
| Git PATH resolution | FIXED | ProcessRunner now uses absolute /usr/bin/git with PATH fallback |

---

## Review History

- **2026-01-26**: Full review including SSH remote features. Found 1 high, 2 medium issues.
- **2026-01-13**: Initial review. All findings resolved or accepted.
