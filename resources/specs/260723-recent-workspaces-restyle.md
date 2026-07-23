# Recent Workspaces Restyle (C3)

## Meta

- Status: Implemented
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
- A second line appears only when it has content: local git repositories show the branch and working-tree state ("main · clean", "main · 3 modified", monochrome); file entries show their containing folder; unavailable entries show a red warning such as "unreachable since yesterday". Rows all share one two-line height; rows with nothing to add leave the second line blank.
- A small dot leads each row: green when the workspace is present or its server answers a probe, grey while a server's state is still unknown, red when a local item is missing, a server does not answer, or a remote last failed.
- Clicking a row opens it (single click; Enter for the keyboard-selected row unchanged). Hovering a row reveals three inline actions: pin/unpin, reveal in Finder (local items only), and remove. The right-click menu keeps its existing entries.
- The whole window uses Redmargin red as its only accent: row selection tint, filter controls, selected icon, pin markers. One highlight serves mouse and keyboard alike: hovering a row makes it the selected row, so the red tint follows the pointer and the arrow keys equally, and only keyboard moves scroll the list.
- The footer buttons look like buttons: "Clear Missing" quiet and bordered, "Clear All..." bordered with red text, "Open" solid red.
- Search, ranking, filtering, pinning, opening, and keyboard behavior stay exactly as they are today.

### Acceptance Criteria

- [x] **A1** Rows show machine and repo in terminal notation, machine in red, and local entries carry no machine part
- [x] **A2** A second row line appears only for local git repositories (branch and state), file entries (containing folder), or unavailable entries (red warning)
- [x] **A3** Each row leads with a green, grey, or red dot matching the workspace's availability
- [x] **A4** Hovering a row shows pin, reveal, and remove actions, and each performs its action
- [x] **A5** No system blue remains anywhere in the window; selection, filters, buttons, and markers all use Redmargin red
- [x] **A6** Searching, filtering, pinning, opening, and keyboard navigation behave the same as before the restyle
- [x] **A7** The full test suite passes on the dev machine

### Out of scope

- Any change to the actions-only command palette (Cmd-Shift-P)
- Grouping rows by machine

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

- [x] **C1** Add `repoSlug`, `machineToken`, and meta-line decision helpers to `RecentWorkspaceItem` in `AppMain/RecentWorkspaces.swift` (parent/name slug, home-directory rule, filename for file kinds, replacing `machineLabel`/`pathText` usage)
- [x] **C2** Add `GitWorkspaceSummary` (branch, changed-file count) with a `summary(for:)` method to `src/Core/Git/GitStatusProvider.swift`, reusing repo-root detection and porcelain parsing plus one branch lookup
- [x] **C3** Add read-only `hasLiveConnection(host:)` to `SSHConnectionManager` in `src/Core/Remote/Client/SSHConnectionManager.swift` and a `WorkspaceAvailability` dot mapping (green/grey/red) next to the row model in `AppMain/RecentWorkspaces.swift`

**Phase 2: Views**

- [x] **C4** Rebuild `AppMain/RecentWorkspaceRowView.swift` to prototype C3: leading dot, fused monospace token with red machine and bright repo, right-aligned faint date, adaptive meta line, hover actions (pin, reveal in Finder for locals, remove), context menu retained
- [x] **C5** Restyle `AppMain/RecentWorkspacesView.swift` to the red accent language: red selection tint, custom red segmented filter controls, styled footer buttons (quiet bordered Clear Missing, red-text bordered Clear All..., solid red Open), red pin toggle and markers
- [x] **C6** Load git summaries asynchronously in `RecentWorkspacesView` for visible local folder rows, cached by storage key, refreshed on window appear and on store changes

**Phase 3: Marco's review findings**

- [x] **C7** Stabilize row size on hover in `RecentWorkspaceRowView.swift` (date hidden by opacity, actions as an overlay) and give the hover action buttons their own hover feedback
- [x] **C8** Drop the amber from the git change count; the meta line is monochrome
- [x] **C9** Probe remote host reachability (ssh batch mode) so the dot shows green for hosts that answer, red for hosts that do not, grey only while unknown
- [x] **C10** Give every row a second line at one uniform height: remote folders get git state via the probe's single ssh round trip (`AppMain/RemoteWorkspaceProber.swift`, path quoted with `shellArgPreservingTilde`), non-repo folders say "no repository", pending state reserves the line

---

## Testing

### Unit Tests (`Tests/RecentWorkspacePresentationTests.swift`)

- [x] **T1** `testRepoSlugDerivation` - parent/name slugs, home-directory rule, file entries, remote path variants
- [x] **T2** `testMetaLineDecision` - git repo shows branch/state, file entries show containing folder, plain remote folders none, unavailable entries show the warning
- [x] **T3** `testAvailabilityDotMapping` - local present/missing, remote with recorded failure, remote idle, remote with live connection

### Integration Tests (`Tests/GitWorkspaceSummaryTests.swift`)

- [x] **T4** `testSummaryOnRealRepo` - temp git repo via `GitTestHelper`: correct branch name, clean state, N-modified count after edits
- [x] **T5** `testSummaryOutsideRepo` - non-repo folder yields no summary
- [x] **T6** `testHasLiveConnectionDoesNotConnect` - the accessor reports state without creating an SSH connection

### Updated Tests (`Tests/RecentWorkspacesTests.swift`, `Tests/PaletteSearchTests.swift`, `Tests/MainMenuTests.swift`)

- [x] **T7** Update row/model assertions from `machineLabel`/`pathText` to the new helpers and accessibility labels; full suite green via `./resources/scripts/build.sh`
- [x] **T8** `testProbeUnreachableHostReturnsFalse` - prober reports an unresolvable host as down; availability mapping updated for probed reachability
- [x] **T9** `testRemoteProbeParsing` - probe output parsing (repo/branch/count, no repo, no dir, garbage, non-zero exit); meta decision covers pending/no-repository/repo states

---

## Build Log

- **C1** `repoSlug`, `machineToken`, `containingFolderText`, `unavailabilityWarning`, `meta(gitSummary:)`, `availability(hasLiveConnection:)` on `RecentWorkspaceItem`; `lastFailureDate` added and maintained by the store (mark/clear/add/relocate). Old `machineLabel`/`pathText` removed.
- **C2** `GitWorkspaceSummary` + `summary(for:)` on `GitStatusProvider`, reusing repo-root detection and porcelain parsing plus one `rev-parse --abbrev-ref HEAD` call.
- **C3** `hasLiveConnection(host:)` dictionary-lookup accessor on `SSHConnectionManager`; `WorkspaceAvailability` mapping in `RecentWorkspaces.swift`.
- **C4** `RecentWorkspaceRowView` rebuilt to prototype C3: state dot (gutter green/grey/red), fused monospace token (brand-red machine, tertiary colon, bright repo), right-aligned faint date, adaptive meta line (git amber count / containing path / red warning), hover actions (pin, reveal for locals, remove), context menu retained. Gutter colors centralized in `BrandColor.swift`.
- **C5** `RecentWorkspacesView` restyled: red selection carried by the row, custom `RedSegmentedControl` for Tier/Kind, red pin toggle, footer with bordered Clear Missing, red-text bordered Clear All..., borderedProminent red-tinted Open.
- **C6** `refreshWorkspaceContext()` loads git summaries for present local folders and live-connection state per remote host off the main actor, cached in `@State`, refreshed on appear and store change.
- **T1-T3** `Tests/RecentWorkspacePresentationTests.swift`: slug derivation (local nested/home-direct, remote ~/, /opt, files), meta decisions (git/path/warning/none, "unreachable since" phrasing, missing local), availability mapping, failure-date bookkeeping.
- **T4-T6** `Tests/GitWorkspaceSummaryTests.swift`: real temp repo via `GitTestHelper` (branch, clean 0, 2 changed after edits), non-repo nil, `hasLiveConnection` leaves `connectStartCount` unchanged on `.shared` (private init forbids a fresh instance).
- **T7** `PaletteSearchTests` moved to `machineToken`/`repoSlug`. Full suite via `./resources/scripts/build.sh`: 438 tests, 0 failures.
- During the walk the windowless test fix was hardened: activation policy alone failed (a `FolderWindowTests` window reached the screen), so `WindowlessTestCase` now also replaces `NSWindow` ordering methods with no-ops in the test process.
- **A1-A3, A6, A7** confirmed via the tests above plus the full green suite (existing search/filter/pin/open tests unchanged and passing). **A4/A5** confirmed by Marco on the running app after the review-round fixes.
- After Marco's follow-up review, rows switched from adaptive height to one uniform two-line height (blank second line when there is no meta), the hover actions aligned to the row's right edge with chevron/pin stepping aside, and the search field regained its editing keys via tested key routing.
- Simplify pass applied: concurrent gated context scans, shared relative-date formatter (`DateFormatting.swift`), shared reveal helper, `RedSegmentedControl.swift` promoted, gutter color comment names its CSS source.
- **C10, T9** Marco rejected blank filler lines; remote folders now carry real git state fetched in the same ssh exec as the reachability probe (REPO/NOREPO/NODIR protocol, parsing unit-tested), non-repo folders read "no repository", and every row keeps one two-line height with the pending state reserving the line invisibly. The former out-of-scope line on remote git information was removed on Marco's instruction.
- **C7-C9, T8** Marco's A4/A5 review found jumping rows, missing button hover states, unwanted amber, and grey dots for live hosts. Fixed: date hidden by opacity with actions overlaid (no layout change), `HoverActionButton` with red hover feedback, monochrome change count (unused amber constant removed), and `RemoteHostProber` (ssh BatchMode, 3s connect timeout) feeding the dot via `RemoteReachability`; probing runs concurrently with the git scans. The former out-of-scope line on probing was removed on Marco's instruction.
