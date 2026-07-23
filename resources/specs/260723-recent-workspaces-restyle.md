# Recent Workspaces Restyle (C3)

## Meta

- Status: Draft
- Branch: feature/recent-workspaces-restyle

---

## Business

### Goal

The Recent Workspaces window (Cmd-P) becomes the switcher Marco actually scans: every row leads with the machine and the repo in terminal notation, shows live context only when it has something to say, signals availability at a glance, and speaks Redmargin's red as its single accent color.

### Proposal

Implement variant C3 of the approved prototype (`resources/specs/260723-recent-workspaces-restyle-3.proto.html`): scp-style row identity, adaptive detail line with git state for local repos, a leading availability dot, inline hover actions, and a consistent red accent language across the whole window.

### Behaviors

- Each row's first line reads like a terminal address: machine name in Redmargin red, a colon, then the repo in bright text (`wraith:engagement`, `spamnesia-dev:opt/spamnesia`). Local entries show no machine part; a plain repo name means "on this Mac" (`dev/detours`, `dotfiles`).
- The repo part is the parent folder plus name (`dev/detours`), or just the name when the workspace sits directly in the home folder (`engagement`). File entries show the file name as the bright part.
- The relative date ("Yesterday", "2 days ago") sits right-aligned on the first line in faint text.
- A second line appears only when it has content: local git repositories show the branch and working-tree state ("main · clean", "main · 3 modified" with the count in amber); file entries show their containing folder; unavailable entries show a red warning such as "unreachable since yesterday". Plain remote folders stay single-line.
- A small dot leads each row: green when the workspace is present or its server connection is live, grey for a remote whose connection is idle, red when a local item is missing or a remote one last failed.
- Hovering a row reveals three inline actions: pin/unpin, reveal in Finder (local items only), and remove. The right-click menu keeps its existing entries.
- The whole window uses Redmargin red as its only accent: row selection tint, filter controls, chevron, selected icon, pin markers.
- The footer buttons look like buttons: "Clear Missing" quiet and bordered, "Clear All..." bordered with red text, "Open" solid red.
- Search, ranking, filtering, pinning, opening, and keyboard behavior stay exactly as they are today.

### Acceptance Criteria

- [ ] **A1** Rows show machine and repo in terminal notation, machine in red, and local entries carry no machine part
- [ ] **A2** A second row line appears only for local git repositories (branch and state), file entries (containing folder), or unavailable entries (red warning)
- [ ] **A3** Each row leads with a green, grey, or red dot matching the workspace's availability
- [ ] **A4** Hovering a row shows pin, reveal, and remove actions, and each performs its action
- [ ] **A5** No system blue remains anywhere in the window; selection, filters, buttons, and markers all use Redmargin red
- [ ] **A6** Searching, filtering, pinning, opening, and keyboard navigation behave the same as before the restyle
- [ ] **A7** The full test suite passes on the dev machine

### Out of scope

- Git information for remote workspaces; remote rows show the date only
- Any change to the actions-only command palette (Cmd-Shift-P)
- Grouping rows by machine
- Live network probing of remote hosts; the dot reflects only state the app already holds

---

## Technical

### Approach

Pure app work on the dev machine, view layer plus two small model additions. The row model (`RecentWorkspaceItem` in `AppMain/RecentWorkspaces.swift`) gains presentation helpers: `repoSlug` (parent/name derivation with the home-directory rule, filename for file kinds), `machineToken` (remote host or nil), and a meta-line decision. Git context comes from a new `GitWorkspaceSummary` API on the existing `GitStatusProvider` (`src/Core/Git/`), which already detects repo roots and parses `git status --porcelain`; it adds one `git rev-parse --abbrev-ref HEAD` call for the branch and a changed-file count. The availability dot maps existing state: local file-system existence (`isLocalMissing`), `lastFailureReason` for failed remotes, and a new read-only `hasLiveConnection(host:)` on `SSHConnectionManager` (`src/Core/Remote/Client/`) that never opens a connection. `RecentWorkspaceRowView` and `RecentWorkspacesView` are restyled to the prototype; git summaries load asynchronously per visible local folder row and are cached by storage key, refreshed when the window appears or the store changes. The HTML prototype is the visual contract; it cannot be lifted verbatim into SwiftUI, so tasks name it as the reference for spacing, color roles, and hierarchy. Colors reuse `Color.redmarginRed` (`AppMain/BrandColor.swift`) and the gutter palette values already shipped in the renderer themes.

### Approach Validation

The design itself was validated with Marco across three prototype rounds (`260723-recent-workspaces-restyle.proto.html`, `-2`, `-3`); C3 is his explicit pick, so no separate UI consultation is needed. Code survey confirmed the enablers exist: `GitStatusProvider.status(for:)` already shells git with repo-root detection and porcelain parsing; `SSHConnectionManager` holds per-host connections that a read-only accessor can expose; `BrandColor.swift` carries the appearance-aware brand red with a test pinning it to the theme palette. The scp `host:path` notation is the established terminal convention for exactly this data, which is why it reads instantly for a developer audience.

### Risks

| Risk | Mitigation |
| ---- | ---------- |
| Shelling git per row slows the window on large recents lists | Summaries load asynchronously off the main actor, only for visible local folder rows, cached by storage key until the store changes |
| Long fused tokens overflow the row | Repo part truncates in the middle; machine part never truncates; date keeps a fixed right slot |
| Hover actions steal clicks from row selection and double-click open | Actions sit in a trailing container with its own hit area; row tap targets are unchanged |
| Red selection tint plus red machine text loses contrast on selected rows | Use the prototype's 16% tint opacity; the brand red text was chosen per appearance for legibility and A5 confirms visually distinguishable states |
| Connection-state lookup accidentally opens SSH connections | `hasLiveConnection(host:)` is a dictionary lookup only; a test asserts no connection is created |

### Implementation Plan

**Phase 1: Model and providers**

- [ ] **C1** Add `repoSlug`, `machineToken`, and meta-line decision helpers to `RecentWorkspaceItem` in `AppMain/RecentWorkspaces.swift` (parent/name slug, home-directory rule, filename for file kinds, replacing `machineLabel`/`pathText` usage)
- [ ] **C2** Add `GitWorkspaceSummary` (branch, changed-file count) with a `summary(for:)` method to `src/Core/Git/GitStatusProvider.swift`, reusing repo-root detection and porcelain parsing plus one branch lookup
- [ ] **C3** Add read-only `hasLiveConnection(host:)` to `SSHConnectionManager` in `src/Core/Remote/Client/SSHConnectionManager.swift` and a `WorkspaceAvailability` dot mapping (green/grey/red) next to the row model in `AppMain/RecentWorkspaces.swift`

**Phase 2: Views**

- [ ] **C4** Rebuild `AppMain/RecentWorkspaceRowView.swift` to prototype C3: leading dot, fused monospace token with red machine and bright repo, right-aligned faint date, adaptive meta line, hover actions (pin, reveal in Finder for locals, remove), context menu retained
- [ ] **C5** Restyle `AppMain/RecentWorkspacesView.swift` to the red accent language: red selection tint, custom red segmented filter controls, styled footer buttons (quiet bordered Clear Missing, red-text bordered Clear All..., solid red Open), red pin toggle and markers
- [ ] **C6** Load git summaries asynchronously in `RecentWorkspacesView` for visible local folder rows, cached by storage key, refreshed on window appear and on store changes

---

## Testing

### Unit Tests (`Tests/RecentWorkspacePresentationTests.swift`)

- [ ] **T1** `testRepoSlugDerivation` - parent/name slugs, home-directory rule, file entries, remote path variants
- [ ] **T2** `testMetaLineDecision` - git repo shows branch/state, file entries show containing folder, plain remote folders none, unavailable entries show the warning
- [ ] **T3** `testAvailabilityDotMapping` - local present/missing, remote with recorded failure, remote idle, remote with live connection

### Integration Tests (`Tests/GitWorkspaceSummaryTests.swift`)

- [ ] **T4** `testSummaryOnRealRepo` - temp git repo via `GitTestHelper`: correct branch name, clean state, N-modified count after edits
- [ ] **T5** `testSummaryOutsideRepo` - non-repo folder yields no summary
- [ ] **T6** `testHasLiveConnectionDoesNotConnect` - the accessor reports state without creating an SSH connection

### Updated Tests (`Tests/RecentWorkspacesTests.swift`, `Tests/PaletteSearchTests.swift`, `Tests/MainMenuTests.swift`)

- [ ] **T7** Update row/model assertions from `machineLabel`/`pathText` to the new helpers and accessibility labels; full suite green via `./resources/scripts/build.sh`

---

## Build Log

Populated at implement time.
