# Preferences

## Meta
- Status: Complete
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
- **Inline code color:** Preset palette (warm/cool/rose/purple/neutral)
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
- `inlineCodeColor`: String enum ("warm", "cool", "rose", "purple", "neutral") - default "warm"

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

**AppMain/RedMarginApp.swift** (modify)
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
- [x] Create `src/Preferences/PreferencesManager.swift`
- [x] Add UserDefaults properties for each setting (matches codebase pattern)
- [x] Make it ObservableObject for SwiftUI observation
- [x] Create shared singleton

**Phase 2: Preferences UI**
- [x] Create `src/Preferences/PreferencesView.swift`
- [x] Add Form with Appearance section (theme picker, inline code color picker)
- [x] Add Git Gutter section (non-repo behavior)
- [x] Add Security section (remote images toggle)

**Phase 3: App Integration**
- [x] Add Settings scene to RedMarginApp
- [x] Verify Cmd+, opens preferences window
- [x] Verify settings persist after quit

**Phase 4: Runtime Updates**
- [x] Modify DocumentView to observe PreferencesManager
- [x] On theme change: call WebView setTheme method
- [x] On gutter preference change: update gutter visibility
- [x] On remote images change: re-render with new option
- [x] On inline code color change: call WebView setInlineCodeColor method

**Phase 5: WebView JS Support**
- [x] Add `window.App.setTheme(theme)` to swap stylesheets (already existed)
- [x] Add logic to block/allow remote images based on option
- [x] Add `window.App.setInlineCodeColor(colorName)` to update --code-text CSS variable
- [x] Test runtime switching (verified via UI automation)

---

## Testing

### Automated Tests

**PreferencesManager tests** in `Tests/PreferencesManagerTests.swift`:

- [x] `testDefaultValues` - Fresh install has expected defaults (system theme, gutter shown, remote images blocked, warm code color)
- [x] `testThemePersists` - Set theme to dark, create new manager instance, verify still dark
- [x] `testRemoteImagesPersists` - Enable remote images, recreate manager, verify still enabled
- [x] `testGutterPreferencePersists` - Change gutter setting, recreate manager, verify persisted
- [x] `testInlineCodeColorPersists` - Change inline code color, recreate manager, verify persisted

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| 2026-01-11 | PASS | 5/5 tests pass |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify preferences window. App does not need to be frontmost - MCP can interact with background apps.

- [x] **RedMargin > Preferences menu exists:** Cmd+, opens Settings window (verified via AppleScript)
- [x] **Preferences window opens:** Window titled "Redmargin Settings" opens
- [x] **Theme picker exists:** pop up button Theme found in window contents
- [x] **Remote images toggle exists:** checkbox "Allow remote images" found
- [x] **Can change theme:** Click theme picker, select "Dark", verify selection changes - persists after quit
- [x] **Inline code color picker exists:** pop up button "Inline Code Color" found
- [x] **Can change inline code color:** Select different preset, verify selection changes - set to Purple
- [x] **Window closes:** Close preferences window, verify it's gone from element list

### Manual Verification (WebView rendering effects)

- [x] **Theme applies to content:** After changing theme, visually confirm WebView updates
- [ ] **Remote images blocked/allowed:** Test with remote image URL, visually confirm behavior
- [x] **Inline code color applies:** After changing color preset, confirm inline `code` color changes in WebView
