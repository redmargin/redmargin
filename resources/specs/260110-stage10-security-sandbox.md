# Security & Sandbox

## Meta
- Status: Draft
- Branch: feature/security-sandbox
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage9-preferences.md

---

## Business

### Problem
Markdown files can contain inline HTML, which could execute malicious scripts. Remote images can leak user activity. The app needs proper sandboxing for App Store distribution. File access must be properly scoped.

### Solution
Sanitize HTML content, block remote loads by default, configure WKWebView security settings, implement security-scoped bookmarks for file access, and prepare for sandbox entitlements.

### Behaviors
- **Script blocking:** No JavaScript from Markdown content executes
- **Remote blocking:** External URLs don't load by default (images, iframes, etc.)
- **Inline HTML:** Safe HTML tags render; dangerous ones stripped
- **File access:** Only files in opened document's directory accessible
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
- Set `WKPreferences.javaScriptEnabled = true` but use `WKContentRuleList` to block inline scripts from content
- Use `WKWebViewConfiguration.limitsNavigationsToAppBoundDomains = true`
- Set `allowsLinkPreview = false`

**Remote Loading:**
- Use `WKContentRuleList` to block all remote URLs by default
- When preference allows remote images, adjust rules to allow `<img>` sources only

**Security-Scoped Bookmarks:**
- When opening a file, create a security-scoped bookmark
- Store in UserDefaults or a dedicated bookmarks file
- On app relaunch, use bookmark to regain access for "Open Recent"

**Sandbox Entitlements:**
- com.apple.security.app-sandbox = true
- com.apple.security.files.user-selected.read-write = true
- com.apple.security.files.bookmarks.app-scope = true

### File Changes

**WebRenderer/src/sanitizer.js** (create)
- HTML sanitizer using allowlist approach
- Allowed tags: p, h1-h6, ul, ol, li, a, img, table, tr, td, th, thead, tbody, code, pre, blockquote, em, strong, del, input (checkbox only)
- Strip all attributes except: href (on a), src/alt (on img), data-sourcepos, type/checked/disabled (on input)
- Remove javascript: and data: URLs from href/src

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

**RedMargin.entitlements** (create)
- App sandbox entitlements for distribution

### Risks

| Risk | Mitigation |
|------|------------|
| Sanitizer too aggressive | Test with common Markdown patterns; ensure tables/code/formatting work |
| Sanitizer too permissive | Security review; test with malicious samples |
| Bookmarks expire or fail | Handle bookmark resolution errors gracefully; fall back to asking user to re-open |
| Content rules don't apply | Test explicitly; rules are async to load |

### Implementation Plan

**Phase 1: HTML Sanitization**
- [ ] Create `WebRenderer/src/sanitizer.js`
- [ ] Implement allowlist-based sanitizer
- [ ] Test with various HTML inputs (safe and malicious)
- [ ] Integrate into index.js rendering pipeline

**Phase 2: WKWebView Security**
- [ ] Configure WKPreferences with security settings
- [ ] Research WKContentRuleList for blocking remote loads
- [ ] Create ContentRuleList.swift for rule generation
- [ ] Apply rules to WKWebView

**Phase 3: Remote Image Control**
- [ ] Implement rule that blocks all remote URLs
- [ ] Implement alternative rule that allows img src only
- [ ] Switch rules based on preference setting
- [ ] Test blocking and allowing

**Phase 4: Security-Scoped Bookmarks**
- [ ] Create `src/App/BookmarkManager.swift`
- [ ] Create bookmark when file opened
- [ ] Store bookmarks in UserDefaults
- [ ] Resolve bookmarks on launch for recent files
- [ ] Integrate with MarkdownDocument

**Phase 5: Sandbox Entitlements**
- [ ] Create `RedMargin.entitlements` file
- [ ] Add app-sandbox entitlement
- [ ] Add file access entitlements
- [ ] Add bookmark entitlements
- [ ] Test app in sandboxed mode

---

## Testing

### Automated Tests

**Sanitizer tests** (JavaScript, in `WebRenderer/tests/`):

- [ ] `testSanitizesScriptTag` - Input with `<script>`, verify removed
- [ ] `testSanitizesEventHandler` - Input with `onclick`, verify removed
- [ ] `testSanitizesJavascriptUrl` - Input with `href="javascript:..."`, verify href removed or neutralized
- [ ] `testAllowsSafeHtml` - Input with `<p><strong>text</strong></p>`, verify preserved
- [ ] `testAllowsTable` - Input with table HTML, verify preserved
- [ ] `testAllowsCheckbox` - Input with checkbox input, verify preserved with type/checked/disabled only
- [ ] `testPreservesSourcepos` - Input with data-sourcepos, verify preserved
- [ ] `testRemovesUnknownAttributes` - Input with `<p data-evil="x">`, verify attribute removed

**BookmarkManager tests** in `Tests/BookmarkManagerTests.swift`:

- [ ] `testCreatesBookmark` - Open file, verify bookmark created
- [ ] `testResolvesBookmark` - Create bookmark, resolve it, verify returns valid URL
- [ ] `testHandlesStaleBookmark` - Create bookmark for temp file, delete file, verify graceful failure

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify app behavior after security changes. App does not need to be frontmost.

- [ ] **App survives XSS attempt:** Create .md with `<script>alert('xss')</script>`, open in app, `list_running_applications` still shows RedMargin (no crash)
- [ ] **App survives event handler attempt:** Create .md with `<img src="x" onerror="alert('xss')">`, verify app still responsive
- [ ] **Open Recent works after restart:** Open file, quit (`osascript -e 'quit app "RedMargin"'`), relaunch, `find_elements_in_app("RedMargin", "$..[?(@.role=='menuItem' && @.title=='Open Recent')]")` shows the file

### Scripted Verification

Create `Tests/Scripts/test-security.sh` to automate:
```bash
# 1. Create malicious test files (XSS, event handlers)
# 2. Open in RedMargin via `open -a RedMargin malicious.md`
# 3. Verify app still running via MCP
# 4. Test Open Recent after quit/relaunch
```

### Manual Verification (visual confirmation)

- [ ] **Safe HTML renders:** Inline HTML table displays correctly
- [ ] **Remote images blocked:** Remote image URL shows nothing or placeholder
- [ ] **Local images work:** Relative image path displays image
