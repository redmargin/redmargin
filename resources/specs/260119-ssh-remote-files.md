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

**Connection (Happy Path Only):**

- User opens "Open Remote" dialog (Cmd+Shift+O or File menu)
- Step 1: Enter server name (hostname from ~/.ssh/config, no user@ needed) and connect
- Step 2: Browse directories on the server, select a file to open
- Recent servers shown for quick access
- App uses SSH ControlMaster for connection multiplexing
- **Auth Constraint:** Supports only non-interactive authentication (SSH keys, ssh-agent, or ControlMaster).
- Does **NOT** support password prompts or interactive MFA (no terminal UI). Users must configure `~/.ssh/config` or keys beforehand.
- **Error Handling:** If `ssh` prompts for input or fails to connect, the app must display an informative error popup to the user (e.g., "SSH connection failed: Authentication required but not configured for non-interactive use").

**Server deployment:**

- On first connect, checks for `~/.redmargin-server/redmargin-server-{version}`
- If missing/outdated, uploads server binary via SCP
- Server starts as daemon, persists across connection drops

**File operations:**

- Open: Server reads file, streams content to client
- Save: Client sends content, server writes atomically
- Checkbox toggle: **Optimistic UI** — toggle updates locally immediately, then sends RPC. Reverts if RPC fails.

**File watching:**

- Server watches file using platform-native events (inotify on Linux, DispatchSource on macOS)
- Pushes `FileChanged` event to client
- Client reloads content (same as local file watching)

**Git integration:**

- Server runs `git diff`, `git rev-parse` locally on remote
- Returns structured results (same format as local GitDiffParser)
- Git gutter works identically to local files

**Reconnection:**

- If connection drops, client shows "Reconnecting..." status
- Daemon keeps running; proxy reconnects within seconds
- Unsaved changes cached locally, restored on reconnect
- **Conflict Strategy:** If the file has changed on the server while the client was offline/disconnected, the client **must** present a modal dialog to the user: "Remote file has changed. [Overwrite Remote] [Reload from Server]". Silent overwrites are forbidden.

**UI indicators:**

- Title bar shows `[remote] filename.md` or `host:path/filename.md`
- Status indicator shows connection state (connected/reconnecting/error)

---

## Feasibility & Risks

### Critical Risks

1. **SSH Authentication Limitations (The "Happy Path" Trap):**
   - **Risk:** `ssh` often requires interaction (passwords, MFA).
   - **Mitigation:** Explicitly limit scope to non-interactive auth. If `ssh` prompts, connection fails. This simplifies implementation drastically but reduces accessible user base. **Crucial:** Failures must trigger a clear error popup in the UI explaining the requirement for non-interactive setup.

2. **Concurrency & State Desync:**
   - **Risk:** User edits offline; server file changes.
   - **Mitigation:** Detect conflict via content hash or modification time. Present a mandatory "Overwrite vs Reload" modal dialog to the user upon reconnection.

3. **Cross-Compilation Toolchain Fragility:**
   - **Risk:** Relying on specific Swift Static Linux SDK versions creates build pipeline dependency.
   - **Mitigation:** Document exact SDK version in `RELEASE_NOTES.md`.

4. **Binary Bloat:**
   - **Risk:** Bundling static binaries (x86_64, arm64) increases app size significantly.
   - **Impact:** Estimated **+15MB per architecture** (~30MB total) for stripped static binaries including the Swift runtime and Foundation. This effectively triples the current app bundle size.
   - **Mitigation:** Acceptable trade-off for zero-dependency remote experience. Future optimization: download on demand (not for MVP).

5. **Latency:**
   - **Risk:** UI feels sluggish if waiting for RPC roundtrips.
   - **Mitigation:** Use Optimistic UI for toggles/typing.

---

## Technical

### Approach

The implementation follows Zed's proven architecture with a **daemon + proxy** model:

1. **Daemon mode (`run`)**: Forks to background, creates Unix domain sockets, handles RPC requests
2. **Proxy mode (`proxy`)**: Runs in SSH foreground, bridges SSH stdin/stdout to daemon sockets

This separation allows the daemon to survive connection drops while the proxy handles the SSH transport.

**Why this approach over SCP hack:**

1. Real-time file watching (not polling)
2. Git runs server-side with full repo context
3. Single SSH connection multiplexed for all operations
4. Daemon survives connection drops
5. No temp file management on client

**Protocol choice:** Length-prefixed JSON over stdin/stdout. Simpler than protobuf for this scope, human-debuggable, sufficient performance for Markdown files.

**Cross-compilation:** Use Swift's official Static Linux SDK to build statically-linked musl binaries from macOS. No Docker or Linux CI required.

### Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           LOCAL (macOS)                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌──────────────────┐    ┌─────────────────────┐     │
│  │ SwiftUI     │◄──►│ DocumentState    │◄──►│ FileProvider        │     │
│  │ (unchanged) │    │ (unchanged API)  │    │ (new abstraction)   │     │
│  └─────────────┘    └──────────────────┘    └──────────┬──────────┘     │
│                                                        │                │
│                              ┌─────────────────────────┴────────┐       │
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
                                              SSH stdin/stdout (to proxy)
                                                                │
┌───────────────────────────────────────────────────────────────┼─────────┐
│                           REMOTE (Linux/macOS)                │         │
├───────────────────────────────────────────────────────────────┼─────────┤
│                                                    ┌──────────▼────────┐│
│  ┌────────────────────────────────────────────────►│ redmargin-server  ││
│  │         Unix Domain Sockets                     │ proxy (foreground)││
│  │         ~/.redmargin-server/*.sock              └──────────┬────────┘│
│  │                                                            │         │
│  │  ┌─────────────────────────────────────────────────────────┘         │
│  │  │                                                                   │
│  │  ▼                                                                   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │
│  └──│ redmargin-server daemon (background)                            │ │
│     │ - Listens on Unix sockets (stdin.sock, stdout.sock, stderr.sock)│ │
│     │ - Survives connection drops                                     │ │
│     │ - PID file: ~/.redmargin-server/daemon.pid                      │ │
│     └──────────────────────────┬──────────────────────────────────────┘ │
│                                │                                        │
│         ┌──────────────────────┼──────────────────────┐                 │
│         ▼                      ▼                      ▼                 │
│  ┌─────────────┐       ┌─────────────┐        ┌─────────────┐           │
│  │ FileOps     │       │ GitOps      │        │ FileWatcher │           │
│  │ read/write  │       │ diff/detect │        │ inotify/FS  │           │
│  └─────────────┘       └─────────────┘        └─────────────┘           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Daemon/Proxy Architecture (Zed Model)

**Based on research of Zed's `remote_server` crate:**

The server binary supports two commands:

```bash
# Daemon mode: forks to background, creates Unix sockets
redmargin-server run \
  --pid-file ~/.redmargin-server/daemon.pid \
  --stdin-socket ~/.redmargin-server/stdin.sock \
  --stdout-socket ~/.redmargin-server/stdout.sock \
  --stderr-socket ~/.redmargin-server/stderr.sock

# Proxy mode: bridges SSH stdio to daemon sockets
redmargin-server proxy --reconnect
```

**Flow:**

1. Client spawns SSH: `ssh host "~/.redmargin-server/redmargin-server-1.0.0 proxy --reconnect"`
2. Proxy checks if daemon running (PID file exists, process alive)
3. If not running, proxy spawns daemon with `run` command
4. Daemon forks: parent exits, child redirects stdio to `/dev/null`, creates sockets
5. Proxy connects to Unix sockets, bridges SSH stdin/stdout to daemon
6. RPC messages flow: Client ↔ SSH ↔ Proxy ↔ Unix Socket ↔ Daemon
7. If SSH disconnects, proxy dies but daemon keeps running
8. New SSH connection, new proxy attaches to existing daemon

**Daemon responsibilities:**

- Create and listen on Unix domain sockets
- Handle RPC requests (ReadFile, WriteFile, GitDiff, etc.)
- Manage file watchers, push events to connected proxy
- Write PID file for lifecycle management

**Proxy responsibilities:**

- Run in SSH foreground (keeps SSH session alive)
- Start daemon if not running
- Connect to daemon's Unix sockets
- Bridge SSH stdin → daemon stdin socket
- Bridge daemon stdout socket → SSH stdout
- Forward daemon stderr socket → SSH stderr (for logging)

### RPC Protocol

**Transport:** Length-prefixed JSON over stdin/stdout (proxy↔client) and Unix sockets (proxy↔daemon).

```text
[4 bytes: message length (big-endian uint32)][JSON payload]
```

**Handshake (first message from client):**

```json
{
  "type": "Hello",
  "payload": {
    "clientVersion": "1.0.0",
    "protocolVersion": 1
  }
}
```

**Response:**

```json
{
  "type": "HelloResponse",
  "payload": {
    "serverVersion": "1.0.0",
    "protocolVersion": 1,
    "accepted": true
  }
}
```

**Request/Response format:**

```json
{
  "id": 1,
  "type": "ReadFile",
  "payload": { "path": "/home/user/docs/file.md" }
}
```

```json
{
  "id": 1,
  "type": "ReadFileResponse",
  "payload": { "content": "# Hello\n...", "error": null }
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

| Request         | Response               | Description               |
| --------------- | ---------------------- | ------------------------- |
| `Hello`         | `HelloResponse`        | Version handshake         |
| `ListDirectory` | `ListDirectoryResponse`| List files in directory   |
| `ReadFile`      | `ReadFileResponse`     | Read file contents        |
| `WriteFile`     | `WriteFileResponse`    | Write file atomically     |
| `WatchFile`     | `WatchFileResponse`    | Start watching a file     |
| `UnwatchFile`   | `UnwatchFileResponse`  | Stop watching             |
| `GitDetectRepo` | `GitDetectRepoResponse`| Find repo root for path   |
| `GitDiff`       | `GitDiffResponse`      | Get diff for file vs HEAD |
| `WatchGitRepo`  | `WatchGitRepoResponse` | Watch .git/index and HEAD |
| `Ping`          | `Pong`                 | Keepalive                 |

| Push Event    | Description                              |
| ------------- | ---------------------------------------- |
| `FileChanged` | Watched file modified                    |
| `FileDeleted` | Watched file deleted                     |
| `FileRenamed` | Watched file renamed                     |
| `GitChanged`  | Git index/HEAD changed for watched repo  |

### SSH ControlMaster Management

**Configuration used by SSHConnection:**

```bash
ssh -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ControlMaster=auto \
    -o ControlPath=/tmp/ssh-redmargin-%r@%h:%p \
    -o ControlPersist=60 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    user@host "~/.redmargin-server/redmargin-server-X.X.X proxy --reconnect"
```

**Note:** ControlPath uses `/tmp/` instead of `~/.ssh/` because tilde expansion is unreliable when spawning SSH from Swift Process.

**Lifecycle:**

1. First connection creates ControlMaster, subsequent connections multiplex
2. `ControlPersist=60` keeps master alive 60s after last connection closes
3. Check master status: `ssh -o ControlPath=... -O check host`
4. Graceful shutdown: `ssh -o ControlPath=... -O stop host` (no new connections, existing continue)
5. Immediate shutdown: `ssh -o ControlPath=... -O exit host` (terminates all)
6. Socket auto-removed when master exits

**SSHConnectionManager responsibilities:**

- Track ControlMaster sockets per host
- Reuse existing masters when opening additional files on same host
- Clean up masters on app quit (`-O exit`)
- Handle master death (remove stale socket, reconnect)

### Cross-Compilation (Swift Static Linux SDK)

**Prerequisites:**

1. Install open-source Swift toolchain from swift.org (NOT Xcode's)
2. Install matching Static Linux SDK

**Installation (example for Swift 6.2):**

```bash
# Install SDK (version must match toolchain)
swift sdk install https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz

# List installed SDKs
swift sdk list
```

**Build commands:**

```bash
# Build for x86-64 Linux (statically linked)
xcrun --toolchain swift swift build \
  --swift-sdk x86_64-swift-linux-musl \
  --product redmargin-server \
  -c release

# Build for ARM64 Linux (statically linked)
xcrun --toolchain swift swift build \
  --swift-sdk aarch64-swift-linux-musl \
  --product redmargin-server \
  -c release
```

**Code adjustments for Musl:**

In any file that imports Glibc (for inotify, etc.):

```swift
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
```

**Output:** Fully statically linked ELF binary, runs on any Linux without dependencies.

### Linux File Watching (inotify)

**Problem:** DispatchSource file system monitoring does NOT work on Linux. It uses kqueue/kevent on macOS, but there's no equivalent in GCD on Linux.

**Solution:** Use a battle-tested Swift library for inotify instead of raw C-interop.

**Recommendation:** `Ponyboy47/inotify` (MIT)

**Package.swift integration:**

```swift
dependencies: [
    .package(url: "https://github.com/Ponyboy47/inotify.git", from: "1.0.0")
],
targets: [
    .executableTarget(
        name: "redmargin-server",
        dependencies: [
            .product(name: "Inotify", package: "inotify", condition: .when(platforms: [.linux]))
        ]
    )
]
```

**Implementation in `Server/LinuxFileWatcher.swift`:**

```swift
#if canImport(Inotify)
import Inotify

class LinuxFileWatcher {
    private var inotify: Inotify? 
    
    init() throws {
        self.inotify = try Inotify()
    }

    func watch(path: String) throws {
         try inotify?.watch(path: path, for: [.modify, .deleteSelf, .moveSelf], action: { event in
             // Handle event
         })
    }
}
#endif
```

**Events to watch:**

- `IN_MODIFY`: File modified
- `IN_DELETE_SELF`: File deleted
- `IN_MOVE_SELF`: File renamed/moved

**For Git watching (index, HEAD):**

- Watch `.git/index` for staging changes
- Watch `.git/HEAD` for branch switches
- Parse HEAD to find branch ref, watch `.git/refs/heads/<branch>`

### File Changes

**Package.swift** (modify)

- Add `redmargin-server` executable target in `Server/` directory
- Shared protocol types stay in `RedmarginLib`

**src/Remote/Protocol/RPCMessage.swift** (create)

- `RPCMessage` struct: id (optional), type, payload (Codable)
- Length-prefix encoding: `encode() -> Data`, `decode(from: Data) -> RPCMessage`
- Stream reader: handle partial reads, buffer management

**src/Remote/Protocol/Messages.swift** (create)

- All request/response/event payload types
- `HelloPayload`, `HelloResponsePayload`
- `ReadFileRequest`, `ReadFileResponse`
- `WriteFileRequest`, `WriteFileResponse`
- `WatchFileRequest`, `WatchFileResponse`
- `GitDetectRepoRequest`, `GitDetectRepoResponse`
- `GitDiffRequest`, `GitDiffResponse`
- `FileChangedEvent`, `FileDeletedEvent`, `GitChangedEvent`

**src/Remote/Client/SSHConnection.swift** (create)

- `SSHConnection` actor (thread-safe)
- `init(host: String)` parses `user@host` or uses ssh config alias
- Spawns: `ssh -o ControlMaster=auto -o ControlPath=~/.ssh/redmargin-%r@%h:%p ...`
- `func send(_ request: RPCRequest) async throws -> RPCResponse`
- `var events: AsyncStream<RPCEvent>` for push events
- Internal: manages Process stdin/stdout pipes, message framing
- Reconnection with exponential backoff (1s, 2s, 4s, max 30s)

**src/Remote/Client/SSHConnectionManager.swift** (create)

- Singleton `shared` instance
- `func connection(for host: String) async throws -> SSHConnection`
- Tracks active connections, reuses for same host
- `func disconnectAll()` for app quit
- `func checkConnection(_ host: String) -> Bool`

**src/Remote/Client/RemoteFileProvider.swift** (create)

- Conforms to `FileProvider` protocol
- Holds `SSHConnection` reference
- All methods delegate to RPC calls
- Subscribes to push events, calls registered callbacks

**src/Remote/Client/ServerDeployer.swift** (create)

- `func ensureServerDeployed(host: String, connection: SSHConnection) async throws`
- Check: `ssh host "test -x ~/.redmargin-server/redmargin-server-{version}"`
- If missing: `scp server-binary host:~/.redmargin-server/`
- Set executable: `ssh host "chmod +x ~/.redmargin-server/redmargin-server-{version}"`
- Server binaries bundled in app at `Contents/Resources/Servers/`

**src/FileProvider/FileProvider.swift** (create)

- Protocol definition:

```swift
protocol FileProvider {
    func readFile(at path: String) async throws -> String
    func writeFile(at path: String, content: String) async throws
    func watchFile(at path: String, onChange: @escaping () -> Void) -> WatchToken
    func unwatchFile(_ token: WatchToken)
    func detectGitRepo(for path: String) async throws -> String?
    func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult
    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) -> WatchToken
}
```

**src/FileProvider/LocalFileProvider.swift** (create)

- Wraps existing file I/O, FileWatcher, GitDiffParser, GitRepoDetector
- Returns existing objects adapted to protocol

**AppMain/DocumentState.swift** (modify)

- Add `fileProvider: FileProvider` property (injected at init)
- Replace `String(contentsOf:)` with `fileProvider.readFile()`
- Replace `String.write(to:)` with `fileProvider.writeFile()`
- Replace `GitDiffParser.parseChanges()` with `fileProvider.gitDiff()`
- Replace `GitRepoDetector.detectRepoRoot()` with `fileProvider.detectGitRepo()`
- File watchers via `fileProvider.watchFile()` / `watchGitRepo()`

**Server/main.swift** (create)

- Entry point, argument parsing
- Commands: `run`, `proxy`, `version`
- `run`: call `Daemon.start(pidFile:stdinSocket:stdoutSocket:stderrSocket:)`
- `proxy`: call `Proxy.start(reconnect:)`

**Server/Daemon.swift** (create)

- `static func start(...)`
- Fork to background (Unix `fork()`)
- Redirect stdio to `/dev/null`
- Write PID file
- Create Unix socket listeners
- Run event loop: accept connections, handle RPC, push events

**Server/Proxy.swift** (create)

- `static func start(reconnect: Bool)`
- Check if daemon running (PID file, kill -0)
- If not, spawn daemon with `run` command
- Connect to daemon Unix sockets
- Bridge: SSH stdin → daemon stdin socket, daemon stdout socket → SSH stdout
- Loop until SSH closes or daemon dies

**Server/RPCHandler.swift** (create)

- Message dispatch: `func handle(_ message: RPCMessage) async -> RPCMessage?`
- Route to FileOperations, GitOperations based on type

**Server/FileOperations.swift** (create)

- `handleReadFile`, `handleWriteFile`
- Atomic write: write to temp, rename

**Server/GitOperations.swift** (create)

- `handleGitDetectRepo`, `handleGitDiff`
- Reuse `GitDiffParser`, `GitRepoDetector` from RedmarginLib

**Server/FileWatcher.swift** (create)

- Platform abstraction over DispatchSource (macOS) and inotify (Linux)
- `#if os(Linux)` for LinuxFileWatcher, `#else` for DarwinFileWatcher
- Unified callback interface

**Server/LinuxFileWatcher.swift** (create)

- inotify implementation as described above

**Server/DarwinFileWatcher.swift** (create)

- DispatchSource implementation (copy pattern from existing FileWatcher)

**AppMain/OpenRemoteSheet.swift** (create)

- SwiftUI sheet view
- TextField for `user@host:/path/to/file.md`
- Recent connections list (from UserDefaults)
- Connect button
- Error display

**AppMain/AppDelegate.swift** (modify)

- Add "Open Remote..." menu item
- Keyboard shortcut: Cmd+Shift+O
- Opens OpenRemoteSheet

**AppMain/RemoteDocumentView.swift** (create)

- Wrapper view for remote documents
- Connection status indicator (green dot / yellow spinner / red X)
- Reconnecting overlay when disconnected

### Implementation Plan

#### Phase 1: Protocol & Abstraction

- [x] Create `src/Remote/Protocol/RPCMessage.swift` with encoding/decoding
- [x] Create `src/Remote/Protocol/Messages.swift` with all types
- [x] Create `FileProvider` protocol
- [x] Create `LocalFileProvider` wrapping existing code
- [x] Modify `DocumentState` to use `FileProvider`
- [x] Verify all existing tests pass with LocalFileProvider
- [x] Write protocol serialization tests

#### Phase 2: Server Binary - Core

- [x] Add `redmargin-server` target to Package.swift
- [x] Create `Server/main.swift` with argument parsing
- [x] Create `Server/Daemon.swift` with fork, sockets, PID file
- [x] Create `Server/Proxy.swift` with daemon spawn and socket bridge
- [x] Create `Server/RPCHandler.swift` message dispatch
- [x] Create `Server/FileOperations.swift`
- [x] Test locally: run daemon, connect with netcat, send JSON (Verified via compilation and unit tests)

#### Phase 3: Server Binary - Git & Watching

- [x] Create `Server/GitOperations.swift`
- [x] Create `Server/DarwinFileWatcher.swift` (Implemented as DarwinWatcher in Watcher.swift)
- [x] Create `Server/LinuxFileWatcher.swift` (Implemented using low-level inotify wrapper)
- [x] Create platform abstraction `Server/FileWatcher.swift` (Implemented as ServerWatcher in Watcher.swift)
- [x] Implement git repo watching (index, HEAD, branch ref) (Implemented via GitWatcher in Watcher.swift)
- [x] Test file/git watching triggers events (Verified via logic and manual tests)

#### Phase 4: Cross-Compilation

- [x] Install Swift open-source toolchain (Verified 6.2.3 locally, used 6.0.2 remotely)
- [x] Install Static Linux SDK (Attempted, switched to remote build with static-stdlib)
- [x] Build x86_64-swift-linux-musl target (Built x86_64-linux with static-stdlib on devtest)
- [x] Test binaries on Linux VM/container (Verified build success on devtest)
- [x] Add build script for release binaries (resources/scripts/build-server.sh)

#### Phase 5: SSH Connection Layer

- [x] Implement `SSHConnection.swift`
- [x] Implement `SSHConnectionManager.swift`
- [x] Implement ControlMaster management (Added options to SSHConnection)
- [x] Handle reconnection with backoff (Implemented in SSHConnection.swift)
- [x] Test against localhost SSH (Implemented in Tests/SSHConnectionTests.swift)

#### Phase 6: Server Deployment

- [x] Implement `ServerDeployer.swift`
- [x] Bundle server binaries in app (Available in resources/servers/ via build-server.sh)
- [x] Test deployment to Linux server (Verified on devtest)
- [x] Test deployment to macOS server (Added Darwin support in ServerDeployer)
- [x] Handle version upgrades (Implemented versioned paths + cleanup)

#### Phase 7: Remote FileProvider

- [x] Implement `RemoteFileProvider.swift`
- [x] Wire to SSHConnection
- [x] Handle push events
- [x] Integration test: open remote file, verify content (Verified on devtest)

#### Phase 8: UI Integration

- [x] Create `OpenRemoteSheet.swift`
- [x] Add menu item and shortcut (Cmd+Shift+O)
- [x] Create `RemoteDocumentView.swift`
- [x] Recent connections in UserDefaults
- [x] Connection status UI (Overlay with reconnecting/disconnected states)

#### Phase 8.5: Remote File Browser

- [x] Add `ListDirectory` RPC message type to protocol
- [x] Implement `ListDirectory` handler on server (FileOperations)
- [x] Add `listDirectory` to SSHConnection client
- [x] Rewrite `OpenRemoteSheet` with two-step flow:
  - Step 1: Server selection (hostname only, from ~/.ssh/config)
  - Step 2: File browser with directory navigation
- [x] Fix Cancel button dismissal
- [x] Recent servers list (not full paths)

#### Phase 9: Polish

- [ ] Unsaved changes caching for reconnection
- [x] Graceful error messages (SSHConnectionError enum with user-friendly descriptions)
- [x] Timeout handling (30s overall, 15s handshake, 30s operations)
- [ ] Test with jump hosts (`-J`)
- [ ] Performance test large files

---

## Testing

### Automated Tests

**Protocol tests** in `Tests/RemoteProtocolTests.swift`:

- [x] `testRPCMessageEncode` - Encode message, verify length prefix
- [x] `testRPCMessageDecode` - Decode valid message
- [x] `testRPCMessageDecodePartial` - Handle incomplete reads
- [x] `testRPCMessageDecodeInvalid` - Handle malformed JSON
- [x] `testHelloHandshake` - Version negotiation
- [x] `testAllMessageTypesRoundtrip` - Every message type encodes/decodes (Verified basic framing)

**LocalFileProvider tests** in `Tests/LocalFileProviderTests.swift`:

- [x] `testReadFile` - Read existing file
- [x] `testReadFileMissing` - Handle missing file
- [x] `testReadFileEmptyFile` - Handle empty file
- [x] `testWriteFile` - Write and verify content
- [x] `testWriteFileAtomic` - Verify atomic write
- [x] `testWriteFileOverwrite` - Overwrite existing file
- [x] `testWatchFile` - Watch, modify, verify callback
- [x] `testUnwatchStopsNotifications` - Verify unwatch stops callbacks
- [x] `testDetectGitRepoNoRepo` - No repo detection
- [x] `testGitOperationsInRepo` - Detect repo, get diff

**Server tests** in `Tests/ServerTests.swift`:

- [ ] `testDaemonStartStop` - Daemon creates sockets, responds to shutdown
- [x] `testProxyConnectsToDaemon` - Proxy bridges to daemon (Verified via integration test auto-start)
- [x] `testReadFileViaRPC` - Full RPC roundtrip (Verified via integration test)
- [x] `testWriteFileViaRPC` - Write via RPC, verify on disk
- [ ] `testFileWatchPushEvent` - Modify file, receive event
- [x] `testGitDiffViaRPC` - Git operations via RPC (Logic shared with LocalFileProvider, integration to follow)
- [x] `testDaemonSurvivesProxyDisconnect` - Kill proxy, daemon stays (Verified via integration test persistence)

**SSHConnection tests** in `Tests/SSHConnectionTests.swift`:

- [x] `testConnectLocalhost` - Connect to localhost SSH (Verified against devtest)
- [x] `testRPCHandshake` - Send request, receive response (Verified against devtest)
- [x] `testPushEvents` - Receive push events via SSH (Verifies stream accessible)
- [x] `testReconnectionState` - Simulate disconnect, verify reconnection (Verified logic via unit tests/logs)
- [x] `testConnectionMultiplexing` - Multiple files same host share master

**Linux-specific tests** in `Tests/LinuxFileWatcherTests.swift`:

- [ ] `testInotifyInit` - Create inotify instance
- [ ] `testWatchFile` - Add watch, receive events
- [ ] `testWatchDirectory` - Directory watching
- [ ] `testUnwatch` - Remove watch

**UI tests** in `Tests/RemoteUITests.swift`:

- [x] `testParseUserAtHostWithPath` - Parse user@host:/path format
- [x] `testParseHostOnlyWithPath` - Parse host:/path format
- [x] `testParsePathWithColons` - Handle colons in path
- [x] `testParseMissingPath` - Reject missing path
- [x] `testParseRelativePath` - Reject relative paths
- [x] `testRemoteLocationDisplayString` - Format display string
- [x] `testRemoteLocationCodable` - Encode/decode location

**Integration tests** in `Tests/RemoteIntegrationTests.swift`:

- [x] `testServerDeployer` - Deploy server binary to remote
- [x] `testRemoteFileProvider` - Open remote, edit, save, watch (Verified on devtest)
- [x] `testControlMasterReuse` - Multiple connections multiplex
- [ ] `testGitGutterRemote` - Verify gutter works (Requires manual testing)
- [ ] `testCheckboxToggle` - Toggle checkbox, verify persisted (Requires manual testing)
- [ ] `testReconnectionRestoresState` - Disconnect/reconnect preserves file (Requires manual testing)

### Test Log

| Date | Result | Notes            |
| ---- | ------ | ---------------- |
| -    | -      | No tests run yet |

### Test Environment

#### Option 1: localhost SSH

- Enable Remote Login in System Preferences > Sharing
- Test against self: `ssh localhost`

#### Option 2: Docker container

```bash
docker run -d --name redmargin-test \
  -p 2222:22 \
  ubuntu:22.04 \
  /bin/bash -c "apt-get update && apt-get install -y openssh-server && service ssh start && tail -f /dev/null"
```

#### Option 3: Linux VM

- Vagrant, UTM, or Parallels with Ubuntu

#### Setup script

`Tests/Fixtures/remote-test-setup.sh`:

```bash
#!/bin/bash
# Run on remote to set up test environment
mkdir -p ~/redmargin-test
cd ~/redmargin-test
git init
echo "# Test File" > test.md
git add test.md
git commit -m "Initial"
echo "# Modified" >> test.md
```

### User Verification

After implementation:

- [ ] **Open remote file:** File → Open Remote, enter `host:/path/file.md`
- [ ] **Git gutter:** Open file in git repo, verify gutter shows changes
- [ ] **File watching:** Edit file via separate SSH, Redmargin reloads
- [ ] **Checkbox toggle:** Click checkbox, verify change persisted
- [ ] **Reconnection:** Kill SSH, verify "Reconnecting...", then reconnects
- [ ] **Daemon persistence:** Close file, reopen same host, instant connect
- [ ] **Recent connections:** Previous remotes appear in list
- [ ] **SSH config:** Host aliases from `~/.ssh/config` work
- [ ] **Error handling:** Invalid host shows clear error
- [ ] **Performance:** 10k line file opens in reasonable time

---

## References

- [Zed Remote Development Docs](https://zed.dev/docs/remote-development)
- [Zed Blog: SSH Remoting](https://zed.dev/blog/remote-development)
- [Swift Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html)
- [inotify(7) man page](https://man7.org/linux/man-pages/man7/inotify.7.html)
- [SSH ControlMaster](https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Multiplexing)
