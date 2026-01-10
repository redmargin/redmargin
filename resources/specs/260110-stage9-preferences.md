# Preferences

## Meta
- Status: Draft
- Branch: feature/preferences
- Dependencies: 260110-stage2-webview-renderer.md, 260110-stage5-git-gutter.md

---

## Business

### Problem
Users need to customize RedMargin's behavior: theme selection, gutter visibility for non-repo files, and whether to load remote images.

### Solution
Create a Preferences window (Cmd+,) with settings stored in UserDefaults. Provide at minimum: theme (light/dark/system), gutter behavior for non-repo files, and remote images toggle.

### Behaviors
- **Cmd+,:** Opens Preferences window
- **Theme:** Light / Dark / System (follows macOS appearance)
- **Gutter for non-repo:** Show empty gutter / Hide gutter entirely
- **Remote images:** Block (default) / Allow
- **Changes apply immediately:** No need to restart or re-open files

---

## Technical

### Approach
Use SwiftUI Settings scene for the preferences window. Store settings in `@AppStorage` (UserDefaults wrapper). Create an observable `PreferencesManager` singleton that other parts of the app can observe for changes.

When preferences change:
- Theme: send message to WebView to switch stylesheet
- Gutter visibility: update DocumentView to show/hide gutter container
- Remote images: send option to WebView renderer

### Preference Keys
- `theme`: String enum ("light", "dark", "system")
- `gutterVisibilityForNonRepo`: String enum ("showEmpty", "hide")
- `allowRemoteImages`: Bool

### File Changes

**src/Preferences/PreferencesManager.swift** (create)
- `@Observable class PreferencesManager`
- Published properties for each setting
- Backed by `@AppStorage` for persistence
- Singleton: `PreferencesManager.shared`

**src/Preferences/PreferencesView.swift** (create)
- SwiftUI view for preferences UI
- Form with sections for Appearance, Git Gutter, Security
- Pickers and toggles for each setting

**src/App/RedMarginApp.swift** (modify)
- Add `Settings { PreferencesView() }` scene
- Ensure Cmd+, opens preferences

**src/Views/DocumentView.swift** (modify)
- Observe PreferencesManager for changes
- Pass updated options to WebView on preference change
- Show/hide gutter based on preference and repo status

**src/Views/MarkdownWebView.swift** (modify)
- Accept theme option and pass to JS
- Accept allowRemoteImages option
- Expose method to update options without full re-render

**WebRenderer/src/index.js** (modify)
- Add `window.App.setTheme(theme)` for runtime theme switching
- Add `window.App.setOptions(options)` for updating options

### Risks

| Risk | Mitigation |
|------|------------|
| Preferences not persisting | Use @AppStorage which writes to UserDefaults; test by quitting and relaunching |
| Theme switch not applying | Call JS method to swap stylesheet; test explicitly |
| Preferences window not opening | Ensure Settings scene is correctly configured |

### Implementation Plan

**Phase 1: Preferences Manager**
- [ ] Create `src/Preferences/PreferencesManager.swift`
- [ ] Add @AppStorage properties for each setting
- [ ] Make it @Observable for SwiftUI observation
- [ ] Create shared singleton

**Phase 2: Preferences UI**
- [ ] Create `src/Preferences/PreferencesView.swift`
- [ ] Add Form with Appearance section (theme picker)
- [ ] Add Git Gutter section (non-repo behavior)
- [ ] Add Security section (remote images toggle)

**Phase 3: App Integration**
- [ ] Add Settings scene to RedMarginApp
- [ ] Verify Cmd+, opens preferences window
- [ ] Verify settings persist after quit

**Phase 4: Runtime Updates**
- [ ] Modify DocumentView to observe PreferencesManager
- [ ] On theme change: call WebView setTheme method
- [ ] On gutter preference change: update gutter visibility
- [ ] On remote images change: re-render with new option

**Phase 5: WebView JS Support**
- [ ] Add `window.App.setTheme(theme)` to swap stylesheets
- [ ] Add logic to block/allow remote images based on option
- [ ] Test runtime switching

---

## Testing

### Automated Tests

**PreferencesManager tests** in `Tests/PreferencesManagerTests.swift`:

- [ ] `testDefaultValues` - Fresh install has expected defaults (system theme, gutter shown, remote images blocked)
- [ ] `testThemePersists` - Set theme to dark, create new manager instance, verify still dark
- [ ] `testRemoteImagesPersists` - Enable remote images, recreate manager, verify still enabled
- [ ] `testGutterPreferencePersists` - Change gutter setting, recreate manager, verify persisted

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify preferences window. App does not need to be frontmost - MCP can interact with background apps.

- [ ] **RedMargin > Preferences menu exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='menuItem' && @.title=='Settings…')]")` finds menu item
- [ ] **Preferences window opens:** Click menu item, then `find_elements_in_app("RedMargin", "$..[?(@.role=='window' && @.title=='Settings')]")` finds window
- [ ] **Theme picker exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='popUpButton' || @.role=='radioGroup')]")` finds theme selector
- [ ] **Remote images toggle exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='checkBox')]")` finds toggle
- [ ] **Can change theme:** Click theme picker, select "Dark", verify selection changes
- [ ] **Window closes:** Close preferences window, verify it's gone from element list

### Manual Verification (WebView rendering effects)

- [ ] **Theme applies to content:** After changing theme, visually confirm WebView updates
- [ ] **Remote images blocked/allowed:** Test with remote image URL, visually confirm behavior
