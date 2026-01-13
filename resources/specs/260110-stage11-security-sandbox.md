# Security & Sandbox

## Meta
- Status: Complete (sandbox deferred - not needed for direct distribution)
- Branch: feature/security-sandbox
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage9-preferences.md

---

## Business

### Problem
Markdown files can contain inline HTML, which could execute malicious scripts. Remote images can leak user activity. File access must be properly scoped.

### Solution
Sanitize HTML content, block remote loads by default, configure WKWebView security settings, and implement security-scoped bookmarks for file access.

### Behaviors
- **Script blocking:** No JavaScript from Markdown content executes
- **Remote blocking:** External URLs don't load by default (images, iframes, etc.)
- **Inline HTML:** Safe HTML tags render; dangerous ones stripped
- **Link navigation:** External links open in system browser; file:// links blocked
- **Local images:** Can load images from any user-readable path (not restricted to document directory)
- **Reopen after restart:** Previously opened files re-openable via security-scoped bookmarks

---

## Technical

### Approach

**HTML Sanitization:** Before rendering, pass Markdown HTML through a sanitizer that:
- Removes `<script>` tags
- Removes event handlers (`onclick`, `onerror`, etc.)
- Removes dangerous URL schemes (`javascript:`, `data:` for scripts)
- Allows safe HTML (formatting, tables, etc.)

**WKWebView Configuration:**
- Disable JavaScript execution from content (only allow bundled app JS)
- Set `WKPreferences.javaScriptEnabled = true` but use sanitizer to strip scripts from content
- Set `allowsLinkPreview = false`
- Use non-persistent data store to reduce tracking state

**Navigation Policy:**
- External links (http/https) open in system browser via NSWorkspace
- mailto: links handled by system mail client
- file:// navigation blocked (security)
- Unknown schemes blocked

**Remote Loading:**
- Use `WKContentRuleList` to block all remote URLs by default
- When preference allows remote images, adjust rules to allow `<img>` sources only

**Security-Scoped Bookmarks:**
- When opening a file, create a security-scoped bookmark
- Store in UserDefaults or a dedicated bookmarks file
- On app relaunch, use bookmark to regain access for "Open Recent"

**Entitlements (for direct distribution):**
- com.apple.security.app-sandbox = false (not required outside App Store)
- com.apple.security.files.user-selected.read-write = true
- com.apple.security.files.bookmarks.app-scope = true

### File Changes

**WebRenderer/src/sanitizer.js** (create)
- HTML sanitizer using allowlist approach
- Allowed tags: p, h1-h6, ul, ol, li, a, img, table, tr, td, th, thead, tbody, code, pre, blockquote, em, strong, del, input (checkbox only), label, div, span, br, hr, etc.
- Strip all attributes except: href (on a), src/alt (on img), data-sourcepos, type/checked/disabled (on input), for (on label)
- URL scheme allowlist for href: http, https, mailto (and relative URLs)
- URL scheme allowlist for src: http, https, file (and relative URLs)
- Allow data: URIs only for img src, and only safe raster MIME types: image/png, image/jpeg, image/gif, image/webp (NOT svg+xml - can contain scripts)

**WebRenderer/src/index.js** (modify)
- Import and use sanitizer before inserting HTML into DOM
- Apply sanitization after markdown-it renders but before DOM insertion

**src/App/ContentRuleList.swift** (create)
- Generate WKContentRuleList JSON for blocking rules
- Block all remote URLs when setting disabled
- Allow image URLs when setting enabled

**src/Views/MarkdownWebView.swift** (modify)
- Configure WKWebView with security settings
- Load content rules on init
- Update rules when preference changes

**src/App/BookmarkManager.swift** (create)
- Create security-scoped bookmarks when opening files
- Store bookmarks persistently
- Resolve bookmarks on app launch
- Clean up stale bookmarks

**src/App/MarkdownDocument.swift** (modify)
- Use BookmarkManager when opening files
- Call startAccessingSecurityScopedResource / stopAccessing

**RedMargin.entitlements** (exists)
- File access and bookmark entitlements (sandbox=false for direct distribution)

### Risks

| Risk | Mitigation |
|------|------------|
| Sanitizer too aggressive | Test with common Markdown patterns; ensure tables/code/formatting work |
| Sanitizer too permissive | Security review; test with malicious samples |
| Bookmarks expire or fail | Handle bookmark resolution errors gracefully; fall back to asking user to re-open |
| Content rules don't apply | Test explicitly; rules are async to load |

### Implementation Plan

**Phase 1: HTML Sanitization**
- [x] Create `WebRenderer/src/sanitizer.js`
- [x] Implement allowlist-based sanitizer
- [x] Test with various HTML inputs (safe and malicious)
- [x] Integrate into index.js rendering pipeline

**Phase 2: WKWebView Security**
- [x] Configure WKPreferences with security settings
- [x] Research WKContentRuleList for blocking remote loads
- [x] Create ContentRuleList.swift for rule generation
- [x] Apply rules to WKWebView

**Phase 3: Remote Image Control**
- [x] Implement rule that blocks all remote URLs
- [x] Implement alternative rule that allows img src only
- [x] Switch rules based on preference setting
- [x] Test blocking and allowing

**Phase 4: Security-Scoped Bookmarks**
- [x] Create `src/App/BookmarkManager.swift`
- [x] Create bookmark when file opened
- [x] Store bookmarks in UserDefaults
- [x] Resolve bookmarks on launch for recent files
- [x] Integrate with AppDelegate (document opening flow)

**Phase 5: Sandbox Entitlements** (DEFERRED)
- [x] Create `RedMargin.entitlements` file (already existed)
- [x] Add file access entitlements
- [x] Add bookmark entitlements
- [~] Enable app-sandbox - DEFERRED (see Sandbox Decision below)

### Sandbox Decision

**Conclusion: App sandbox is not required for direct distribution.**

Research conducted 2026-01-13 found that sandbox is only mandatory for Mac App Store distribution. For apps distributed directly (download, Homebrew, etc.), only these are required:

1. **Code signing** with Developer ID certificate
2. **Notarization** via Apple (which requires hardened runtime)

With proper signing + notarization, users see no Gatekeeper warnings - the app opens normally.

**Industry practice:** Major IDEs and editors (VS Code, Zed, Sublime Text, Ghostty) are all non-sandboxed. They need full filesystem access which sandbox makes impractical.

**Technical blocker if sandbox were needed:** WKWebView cannot load local `file://` URLs when sandboxed. Would require implementing a custom `WKURLSchemeHandler` to serve local files via a custom URL scheme (e.g., `redmargin://`).

**Recommendation:** If Mac App Store distribution is desired in the future, revisit sandbox as a separate stage. The current entitlements file is prepared with bookmark support for that scenario.

---

## Testing

### Automated Tests

**Sanitizer tests** (JavaScript, in `WebRenderer/tests/`):

- [x] `testSanitizesScriptTag` - Input with `<script>`, verify removed
- [x] `testSanitizesEventHandler` - Input with `onclick`, verify removed
- [x] `testSanitizesJavascriptUrl` - Input with `href="javascript:..."`, verify href removed or neutralized
- [x] `testAllowsSafeHtml` - Input with `<p><strong>text</strong></p>`, verify preserved
- [x] `testAllowsTable` - Input with table HTML, verify preserved
- [x] `testAllowsCheckbox` - Input with checkbox input, verify preserved with type/checked/disabled only
- [x] `testPreservesSourcepos` - Input with data-sourcepos, verify preserved
- [x] `testRemovesUnknownAttributes` - Input with `<p data-evil="x">`, verify attribute removed

**BookmarkManager tests** in `Tests/BookmarkManagerTests.swift`:

- [x] `testCreatesBookmark` - Open file, verify bookmark created
- [x] `testResolvesBookmark` - Create bookmark, resolve it, verify returns valid URL
- [x] `testHandlesStaleBookmark` - Create bookmark for temp file, delete file, verify graceful failure

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 260112 | PASS | 31 JS sanitizer tests, 7 BookmarkManager tests (91 total Swift tests) |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app behavior after security changes. App does not need to be frontmost.

- [x] **App survives XSS attempt:** Create .md with `<script>alert('xss')</script>`, open in app, `list_running_applications` still shows RedMargin (no crash)
- [x] **App survives event handler attempt:** Create .md with `<img src="x" onerror="alert('xss')">`, verify app still responsive
- [x] **Open Recent works after restart:** Open file, quit (`osascript -e 'quit app "RedMargin"'`), relaunch - app relaunches and restores session

### Scripted Verification

Create `Tests/Scripts/test-security.sh` to automate:
```bash
# 1. Create malicious test files (XSS, event handlers)
# 2. Open in RedMargin via `open -a RedMargin malicious.md`
# 3. Verify app still running via MCP
# 4. Test Open Recent after quit/relaunch
```

### Manual Verification (visual confirmation)

- [x] **Safe HTML renders:** Inline HTML table displays correctly
- [x] **Remote images blocked:** Remote image URL shows nothing or placeholder
- [x] **Local images work:** Relative image path displays image
