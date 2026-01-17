# SSH Remote File Editing

## Meta
- Status: Draft
- Branch: feature/ssh-remote-files
- Dependencies: All existing stages (this builds on the complete local implementation)

---

## Business

### Problem
Redmargin only opens files from the local filesystem. Users who work with Markdown files on remote servers (accessible via SSH) must either:
- Copy files locally, losing real-time sync
- Use a different tool entirely
- SSH in and use terminal-based editors

VS Code and Zed solve this with remote development features. Redmargin should offer the same capability for its core use case: viewing and lightly editing Markdown files with Git gutter support.

### Solution
Deploy a headless server binary to the remote host that handles file operations, Git commands, and file watching. The local Redmargin app communicates with this server over SSH using a binary RPC protocol. The architecture mirrors Zed's approach: computation happens remotely, UI renders locally.

### Behaviors

**Connection:**
- User opens "Connect to Server" dialog (Cmd+Shift+O or File menu)
- Enters `user@host:/path/to/file.md` or selects from recent connections
- App uses SSH ControlMaster for connection multiplexing
- Inherits `~/.ssh/config` settings (no custom credential UI)

**Server deployment:**
- On first connect, checks for `~/.redmargin-server/redmargin-server-{version}`
- If missing/outdated, uploads server binary via SCP
- Server starts as daemon, persists across connection drops

**File operations:**
- Open: Server reads file, streams content to client
- Save: Client sends content, server writes atomically
- Checkbox toggle: Same as local — modify content, save

**File watching:**
- Server watches file using platform-native events (inotify/FSEvents)
- Pushes `FileChanged` event to client
- Client reloads content (same as local file watching)

**Git integration:**
- Server runs `git diff`, `git rev-parse` locally on remote
- Returns structured results (same format as local GitDiffParser)
- Git gutter works identically to local files

**Reconnection:**
- If connection drops, client shows "Reconnecting..." status
- Daemon keeps running; reconnects within seconds
- Unsaved changes cached locally, restored on reconnect

**UI indicators:**
- Title bar shows `[remote] filename.md` or `host:path/filename.md`
- Status indicator shows connection state (connected/reconnecting/error)

---

## Technical

### Approach

The implementation follows Zed's proven architecture: a headless server binary runs on the remote host, communicating with the local client over SSH stdin/stdout using a length-prefixed binary protocol.

**Why this approach over SCP hack:**
1. Real-time file watching (not polling)
2. Git runs server-side with full repo context
3. Single SSH connection multiplexed for all operations
4. Daemon survives connection drops
5. No temp file management on client

**Protocol choice:** Length-prefixed JSON over stdin/stdout. Simpler than protobuf for this scope, human-debuggable, sufficient performance for Markdown files.

**Server binary:** Built from same Swift Package as a separate executable target. Statically linked where possible. Falls back to dynamic linking on macOS remotes.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           LOCAL (macOS)                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────────┐    │
│  │ SwiftUI     │◄──►│ DocumentState    │◄──►│ FileProvider        │    │
│  │ (unchanged) │    │ (unchanged API)  │    │ (new abstraction)   │    │
│  └─────────────┘    └──────────────────┘    └──────────┬──────────┘    │
│                                                         │               │
│                              ┌──────────────────────────┴───────┐       │
│                              ▼                                  ▼       │
│                     ┌─────────────────┐              ┌─────────────────┐│
│                     │ LocalProvider   │              │ RemoteProvider  ││
│                     │ (current impl)  │              │ (new)           ││
│                     └─────────────────┘              └────────┬────────┘│
│                                                               │         │
│                                                    ┌──────────▼────────┐│
│                                                    │ SSHConnection     ││
│                                                    │ (ControlMaster)   ││
│                                                    └──────────┬────────┘│
└───────────────────────────────────────────────────────────────┼─────────┘
                                                                │
                                              SSH (stdin/stdout RPC)
                                                                │
┌───────────────────────────────────────────────────────────────┼─────────┐
│                           REMOTE (Linux/macOS)                │         │
├───────────────────────────────────────────────────────────────┼─────────┤
│                                                    ┌──────────▼────────┐│
│                                                    │ redmargin-server  ││
│                                                    │ (daemon)          ││
│                                                    └──────────┬────────┘│
│                              ┌────────────────┬───────────────┼─────────┤
│                              ▼                ▼               ▼         │
│                     ┌─────────────┐   ┌─────────────┐  ┌─────────────┐  │
│                     │ FileOps     │   │ GitOps      │  │ FileWatcher │  │
│                     │ read/write  │   │ diff/detect │  │ inotify/FS  │  │
│                     └─────────────┘   └─────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### RPC Protocol

**Transport:** SSH connection with ControlMaster. Server reads from stdin, writes to stdout. Each message is length-prefixed:

```
[4 bytes: message length (big-endian uint32)][JSON payload]
```

**Message format:**

```json
{
  "id": 1,
  "type": "ReadFile",
  "payload": { ... }
}
```

**Response format:**

```json
{
  "id": 1,
  "type": "ReadFileResponse",
  "payload": { ... }
}
```

**Push events (no request ID):**

```json
{
  "type": "FileChanged",
  "payload": { "path": "/home/user/docs/file.md" }
}
```

**Message types:**

| Request | Response | Description |
|---------|----------|-------------|
| `ReadFile` | `ReadFileResponse` | Read file contents |
| `WriteFile` | `WriteFileResponse` | Write file atomically |
| `WatchFile` | `WatchFileResponse` | Start watching a file |
| `UnwatchFile` | `UnwatchFileResponse` | Stop watching |
| `GitDetectRepo` | `GitDetectRepoResponse` | Find repo root for path |
| `GitDiff` | `GitDiffResponse` | Get diff for file vs HEAD |
| `Ping` | `Pong` | Keepalive |

| Push Event | Description |
|------------|-------------|
| `FileChanged` | Watched file modified |
| `FileDeleted` | Watched file deleted |
| `FileRenamed` | Watched file renamed |
| `GitChanged` | Git index/HEAD changed |

### File Changes

**New package target in `Package.swift`:**
- Add `redmargin-server` executable target
- Depends on shared protocol types from RedmarginLib

**src/Remote/Protocol/** (create directory)

**src/Remote/Protocol/RPCMessage.swift** (create)
- `RPCMessage` struct: id, type, payload (Codable)
- `RPCRequest` enum with associated payloads for each request type
- `RPCResponse` enum with associated payloads for each response type
- `RPCEvent` enum for push events
- Length-prefix encoding/decoding helpers

**src/Remote/Protocol/FileMessages.swift** (create)
- `ReadFileRequest`: path
- `ReadFileResponse`: content (String), error (optional)
- `WriteFileRequest`: path, content
- `WriteFileResponse`: success, error (optional)
- `WatchFileRequest`: path
- `WatchFileResponse`: success, error (optional)
- `FileChangedEvent`: path

**src/Remote/Protocol/GitMessages.swift** (create)
- `GitDetectRepoRequest`: path
- `GitDetectRepoResponse`: repoRoot (optional), error (optional)
- `GitDiffRequest`: path, repoRoot
- `GitDiffResponse`: changes (GitChangeResult JSON), error (optional)
- `GitChangedEvent`: repoRoot

**src/Remote/Client/SSHConnection.swift** (create)
- `SSHConnection` class
- `init(host: String)` — host from ssh config or user@host format
- Uses ProcessRunner to spawn `ssh -o ControlMaster=auto -o ControlPath=~/.ssh/redmargin-%r@%h:%p`
- Manages stdin/stdout pipes to remote server process
- `func send(_ request: RPCRequest) async throws -> RPCResponse`
- `var events: AsyncStream<RPCEvent>` — push events from server
- Reconnection logic with exponential backoff

**src/Remote/Client/SSHConnectionManager.swift** (create)
- Singleton managing active connections
- Connection pooling per host
- `func connection(for host: String) async throws -> SSHConnection`
- Handles ControlMaster lifecycle

**src/Remote/Client/RemoteFileProvider.swift** (create)
- Implements `FileProvider` protocol
- `func readFile(at path: String) async throws -> String`
- `func writeFile(at path: String, content: String) async throws`
- `func watchFile(at path: String, onChange: @escaping () -> Void) -> WatchToken`
- `func unwatchFile(_ token: WatchToken)`
- `func detectGitRepo(for path: String) async throws -> String?`
- `func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult`

**src/Remote/Client/ServerDeployer.swift** (create)
- `func ensureServerDeployed(on connection: SSHConnection) async throws`
- Checks `~/.redmargin-server/redmargin-server-{version}` exists
- If not, uploads via `scp` from app bundle or downloads from release URL
- Marks executable with `chmod +x`

**src/FileProvider/FileProvider.swift** (create)
- Protocol abstracting file operations
- `protocol FileProvider`
- Methods: readFile, writeFile, watchFile, unwatchFile, detectGitRepo, gitDiff
- Both local and remote providers conform

**src/FileProvider/LocalFileProvider.swift** (create)
- Implements `FileProvider` for local filesystem
- Wraps existing `String(contentsOf:)`, `String.write(to:)` calls
- Wraps existing `FileWatcher`, `GitDiffParser`, `GitRepoDetector`

**AppMain/DocumentState.swift** (modify)
- Add `fileProvider: FileProvider` property
- Replace direct file I/O with fileProvider calls
- Replace direct GitDiffParser/GitRepoDetector calls with fileProvider calls
- Keep FileWatcher integration but route through fileProvider.watchFile

**Server binary (new executable target):**

**Server/main.swift** (create in new Server/ directory)
- Entry point for redmargin-server
- Parses command-line args (--daemon, --version)
- Creates RPCServer instance
- Runs event loop

**Server/RPCServer.swift** (create)
- Reads length-prefixed messages from stdin
- Dispatches to handlers
- Writes responses to stdout
- Manages file watchers, pushes events

**Server/FileOperations.swift** (create)
- `func handleReadFile(_ request: ReadFileRequest) -> ReadFileResponse`
- `func handleWriteFile(_ request: WriteFileRequest) -> WriteFileResponse`
- Atomic writes using temp file + rename

**Server/GitOperations.swift** (create)
- `func handleGitDetectRepo(_ request: GitDetectRepoRequest) -> GitDetectRepoResponse`
- `func handleGitDiff(_ request: GitDiffRequest) -> GitDiffResponse`
- Reuses GitDiffParser and GitRepoDetector logic (shared via RedmarginLib)

**Server/ServerFileWatcher.swift** (create)
- Cross-platform file watching
- Linux: inotify via DispatchSource or direct syscalls
- macOS: existing DispatchSource approach
- Emits FileChanged/FileDeleted/FileRenamed events

**AppMain/OpenRemoteSheet.swift** (create)
- SwiftUI sheet for "Connect to Server"
- Text field for `user@host:/path/to/file.md`
- Recent connections list (stored in UserDefaults)
- Connect button triggers connection + file open

**AppMain/AppDelegate.swift** (modify)
- Add "Open Remote..." menu item (Cmd+Shift+O)
- Handle opening remote URLs

**AppMain/RemoteDocumentView.swift** (create)
- Wrapper around DocumentView for remote files
- Shows connection status indicator
- Handles reconnection UI

### Risks

| Risk | Mitigation |
|------|------------|
| Server binary compatibility across Linux distros | Build with static linking where possible; provide multiple builds (glibc, musl) |
| SSH connection drops frequently | ControlMaster with keepalive; daemon mode survives drops; auto-reconnect |
| Large file transfers slow | Stream content in chunks; show progress for large files |
| Git operations slow over high-latency connections | Cache repo root detection; batch operations where possible |
| Server deployment fails (permissions, disk space) | Clear error messages; manual deployment instructions as fallback |
| File watching overwhelmed on busy repos | Debounce events server-side; rate-limit push events |
| Protocol versioning | Include version in handshake; server refuses incompatible clients |
| Security: malicious server binary execution | Server only runs in user's home dir; requires explicit user action to connect |

### Implementation Plan

**Phase 1: Protocol Definition**
- [ ] Create `src/Remote/Protocol/` directory structure
- [ ] Implement `RPCMessage.swift` with encoding/decoding
- [ ] Implement `FileMessages.swift` request/response types
- [ ] Implement `GitMessages.swift` request/response types
- [ ] Write unit tests for message serialization

**Phase 2: FileProvider Abstraction**
- [ ] Create `FileProvider` protocol in `src/FileProvider/FileProvider.swift`
- [ ] Create `LocalFileProvider` wrapping existing file operations
- [ ] Modify `DocumentState` to use `FileProvider` instead of direct I/O
- [ ] Verify all existing functionality works with LocalFileProvider
- [ ] Write tests for LocalFileProvider

**Phase 3: Server Binary - Core**
- [ ] Add `redmargin-server` target to Package.swift
- [ ] Create `Server/main.swift` entry point
- [ ] Create `Server/RPCServer.swift` with message loop
- [ ] Implement `Server/FileOperations.swift` (read/write)
- [ ] Write integration tests for server file operations

**Phase 4: Server Binary - Git**
- [ ] Implement `Server/GitOperations.swift`
- [ ] Reuse GitDiffParser and GitRepoDetector from RedmarginLib
- [ ] Write integration tests for server git operations

**Phase 5: Server Binary - File Watching**
- [ ] Implement `Server/ServerFileWatcher.swift`
- [ ] Linux inotify support
- [ ] macOS DispatchSource support (reuse existing pattern)
- [ ] Push events to client
- [ ] Write tests for file watching

**Phase 6: SSH Connection Layer**
- [ ] Implement `SSHConnection.swift` with ControlMaster
- [ ] Implement `SSHConnectionManager.swift` for connection pooling
- [ ] Handle connection lifecycle (connect, disconnect, reconnect)
- [ ] Write tests for connection management

**Phase 7: Server Deployment**
- [ ] Implement `ServerDeployer.swift`
- [ ] Build server binary for macOS (arm64, x86_64)
- [ ] Build server binary for Linux (glibc, musl)
- [ ] Include binaries in app bundle or set up download mechanism
- [ ] Test deployment to various remote hosts

**Phase 8: Remote FileProvider**
- [ ] Implement `RemoteFileProvider.swift`
- [ ] Wire up to SSHConnection for RPC calls
- [ ] Handle push events (FileChanged, GitChanged)
- [ ] Write integration tests with real SSH connections

**Phase 9: UI Integration**
- [ ] Create `OpenRemoteSheet.swift`
- [ ] Add menu item and keyboard shortcut
- [ ] Create `RemoteDocumentView.swift` with status indicator
- [ ] Store recent connections in UserDefaults
- [ ] Handle reconnection UI states

**Phase 10: Polish & Edge Cases**
- [ ] Handle connection errors gracefully
- [ ] Implement unsaved changes caching for reconnection
- [ ] Add connection timeout handling
- [ ] Test with various SSH configurations (jump hosts, keys, etc.)
- [ ] Performance testing with large files and high-latency connections

---

## Testing

### Automated Tests

**Protocol tests** in `Tests/RemoteProtocolTests.swift`:
- [ ] `testRPCMessageEncode` - Encode message, verify length prefix and JSON
- [ ] `testRPCMessageDecode` - Decode valid message
- [ ] `testRPCMessageDecodeInvalid` - Handle malformed input
- [ ] `testReadFileRequestRoundtrip` - Encode/decode ReadFileRequest
- [ ] `testWriteFileRequestRoundtrip` - Encode/decode WriteFileRequest
- [ ] `testGitDiffResponseRoundtrip` - Encode/decode GitDiffResponse with GitChangeResult
- [ ] `testFileChangedEventRoundtrip` - Encode/decode push event

**LocalFileProvider tests** in `Tests/LocalFileProviderTests.swift`:
- [ ] `testReadFile` - Read existing file
- [ ] `testReadFileMissing` - Handle missing file
- [ ] `testWriteFile` - Write and verify content
- [ ] `testWriteFileAtomic` - Verify atomic write (temp + rename)
- [ ] `testWatchFile` - Watch file, modify, verify callback
- [ ] `testDetectGitRepo` - Detect repo root
- [ ] `testGitDiff` - Get diff for modified file

**Server tests** in `Tests/ServerTests.swift` (requires server binary):
- [ ] `testServerStartup` - Server starts and responds to Ping
- [ ] `testServerReadFile` - Read file via RPC
- [ ] `testServerWriteFile` - Write file via RPC
- [ ] `testServerGitDiff` - Git diff via RPC
- [ ] `testServerFileWatch` - Watch file, modify, receive event
- [ ] `testServerMultipleClients` - Handle concurrent requests

**SSHConnection tests** in `Tests/SSHConnectionTests.swift`:
- [ ] `testConnectToLocalhost` - Connect to localhost (requires SSH setup)
- [ ] `testSendReceive` - Send request, receive response
- [ ] `testPushEvents` - Receive push events
- [ ] `testReconnect` - Handle connection drop and reconnect

**Integration tests** in `Tests/RemoteIntegrationTests.swift`:
- [ ] `testOpenRemoteFile` - Full flow: connect, open, read content
- [ ] `testEditRemoteFile` - Edit and save remote file
- [ ] `testRemoteGitGutter` - Verify git gutter works for remote file
- [ ] `testRemoteFileWatch` - Modify remote file externally, verify reload
- [ ] `testCheckboxToggleRemote` - Toggle checkbox on remote file

### Test Log

| Date | Result | Notes |
|------|--------|-------|
| — | — | No tests run yet |

### Test Environment Setup

Testing requires SSH access to a remote host. Options:
1. **localhost:** Enable SSH in System Preferences, test against self
2. **Docker container:** Spin up Linux container with SSH
3. **VM:** Use Vagrant or similar for Linux testing

Create `Tests/Fixtures/remote-test-setup.sh` script that:
- Creates test directory structure on remote
- Initializes test git repo
- Creates test markdown files

### User Verification

After implementation, Marco verifies:

- [ ] **Open remote file:** File → Open Remote, enter `host:/path/file.md`, content displays
- [ ] **Git gutter works:** Open file in git repo, make local changes, gutter shows diff
- [ ] **File watching:** Edit file on remote (via separate SSH session), Redmargin reloads
- [ ] **Checkbox toggle:** Click checkbox, file saves to remote, change persists
- [ ] **Reconnection:** Disconnect network briefly, verify "Reconnecting..." appears, then reconnects
- [ ] **Recent connections:** Previously opened remote files appear in recent list
- [ ] **SSH config inheritance:** Hosts defined in `~/.ssh/config` work without extra configuration
- [ ] **Error handling:** Invalid host shows clear error message
- [ ] **Large file:** Open 10k line markdown file over SSH, verify reasonable performance
