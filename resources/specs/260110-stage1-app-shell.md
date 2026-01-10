# App Shell

## Meta
- Status: Draft
- Branch: feature/app-shell
- Dependencies: None (foundation spec)

---

## Business

### Problem
RedMargin needs a basic macOS application structure before any features can be built. Users need to open Markdown files via File menu, drag/drop, Finder's "Open With", and access recent files.

### Solution
Create a minimal SwiftUI app with window management, file opening (multiple methods), and recent files tracking. This provides the shell that all other features will build upon.

### Behaviors
- **File > Open (Cmd+O):** Opens file picker filtered to `.md` and `.markdown` files
- **Drag/drop:** Drop a Markdown file onto the app icon or window to open it
- **Open With:** Right-click a Markdown file in Finder → Open With → RedMargin
- **File > Open Recent:** Shows recently opened files; selecting one opens it
- **Window title:** Shows the filename (e.g., "README.md")
- **Multiple windows:** Each opened file gets its own window

---

## Technical

### Approach
Use SwiftUI's `DocumentGroup` or a custom `WindowGroup` with `@Environment(\.openDocument)`. The app will be document-based, where each Markdown file opens in its own window. For MVP, the window will display a placeholder text view showing the raw Markdown content (rendering comes in the next spec).

Use `NSDocumentController` for recent files management - it handles this automatically for document-based apps. Register the app to handle `.md` and `.markdown` file types via Info.plist.

### File Changes

**src/App/RedMarginApp.swift** (create)
- Main `@main` App struct using SwiftUI
- Use `DocumentGroup` with a custom `MarkdownDocument` type
- Configure scene to open `.md` and `.markdown` files

**src/App/MarkdownDocument.swift** (create)
- Conform to `FileDocument` protocol
- `readableContentTypes`: UTType for Markdown (`.md`, `.markdown`)
- `init(configuration:)`: Load file content as String
- Store the file content and URL for later use by the renderer

**src/Views/DocumentView.swift** (create)
- Main view displayed in each document window
- For this spec: simple `Text` view showing raw Markdown content (placeholder)
- Accept `MarkdownDocument` as binding

**Info.plist additions** (create or update)
- Add document types for `public.markdown` and `net.daringfireball.markdown`
- Add exported/imported UTI declarations if needed
- Set CFBundleDocumentTypes with LSHandlerRank = Owner

**resources/scripts/build.sh** (create)
- Shell script to build the app with `swift build`
- Bundle the executable into the app bundle structure
- Copy WebRenderer assets (for future specs)

### Risks

| Risk | Mitigation |
|------|------------|
| UTType for Markdown not recognized | Use both `public.markdown` and the Daring Fireball UTI; test with various .md files |
| Recent files not persisting | Verify `NSDocumentController` is being used; it handles this automatically |
| Drag/drop not working | Ensure proper UTI registration in Info.plist; test explicitly |

### Implementation Plan

**Phase 1: Project Setup**
- [ ] Create `Package.swift` with SwiftUI/AppKit dependencies, macOS 14.0+ target
- [ ] Create `src/App/RedMarginApp.swift` with basic `@main` App struct
- [ ] Create placeholder `src/Views/DocumentView.swift` showing "RedMargin" text
- [ ] Verify app launches with `swift run`

**Phase 2: Document Model**
- [ ] Create `src/App/MarkdownDocument.swift` conforming to `FileDocument`
- [ ] Implement `readableContentTypes` for Markdown UTTypes
- [ ] Implement `init(configuration:)` to read file as UTF-8 String
- [ ] Store file URL via `FileDocumentConfiguration`
- [ ] Update `RedMarginApp.swift` to use `DocumentGroup` with `MarkdownDocument`

**Phase 3: File Opening**
- [ ] Update `DocumentView.swift` to display document content as raw text
- [ ] Test File > Open dialog opens and filters to Markdown files
- [ ] Test drag/drop onto dock icon opens file
- [ ] Test drag/drop onto window opens file (or opens in new window)
- [ ] Verify window title shows filename

**Phase 4: Recent Files & Open With**
- [ ] Verify File > Open Recent menu populates automatically
- [ ] Create/update Info.plist with document type declarations
- [ ] Test "Open With" from Finder context menu
- [ ] Create `resources/scripts/build.sh` for building the app bundle

---

## Testing

### Automated Tests

Tests go in `Tests/AppShellTests.swift`. Focus on the document model since UI testing requires XCUITest (covered in User Verification).

- [ ] `testMarkdownDocumentLoadsContent` - Create a temp .md file, initialize MarkdownDocument, verify content property matches file content
- [ ] `testMarkdownDocumentHandlesUTF8` - Load a file with Unicode characters (emoji, CJK), verify content is correct
- [ ] `testMarkdownDocumentHandlesEmptyFile` - Load an empty .md file, verify content is empty string (not nil or error)
- [ ] `testMarkdownDocumentHandlesLargeFile` - Load a 10,000 line .md file, verify it loads without error

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### MCP UI Verification

Use `macos-ui-automation` MCP to verify UI behavior. Run RedMargin first, then execute these checks:

- [ ] **App launches:** `list_running_applications` shows RedMargin
- [ ] **File > Open menu exists:** `find_elements_in_app("RedMargin", "$..[?(@.role=='menuItem' && @.title=='Open…')]")` finds the menu item
- [ ] **Window title shows filename:** After opening a file, `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` returns window with correct title
- [ ] **Multiple windows:** Open 3 files, `find_elements_in_app("RedMargin", "$..[?(@.role=='window')]")` returns 3 windows
- [ ] **Open Recent menu populated:** `find_elements_in_app("RedMargin", "$..[?(@.role=='menuItem' && @.title=='Open Recent')]")` then check submenu items

### Manual Verification (cannot automate)

- [ ] **Drag to dock:** Drag a .md file to the dock icon, verify it opens
- [ ] **Finder Open With:** Right-click a .md file in Finder, Open With > RedMargin works
