# SSH Remote Connection Debugging

## Problem Statement

SSH remote file connections fail on first attempt but succeed on second attempt. The app deploys the server binary, shows "Connecting to [host]...", then fails with a handshake timeout. Clicking the server name again works immediately.

## Symptoms

1. First connection: Deploys server, times out on Hello handshake
2. Second connection: Works immediately (daemon already running)
3. Log shows: `Timeout waiting for response id=1`
4. Subsequent retries show: `ERROR: Not in connected/connecting state`

## Architecture

```
┌─────────┐     SSH      ┌─────────┐    Unix     ┌─────────┐
│  Client │ ──────────── │  Proxy  │ ─────────── │  Daemon │
│  (Mac)  │   stdin/out  │ (Linux) │   Socket    │ (Linux) │
└─────────┘              └─────────┘             └─────────┘
```

- **Client**: macOS app, establishes SSH connection, sends RPC messages
- **Proxy**: Bridges SSH stdin/stdout to daemon Unix socket, starts daemon if needed
- **Daemon**: Long-running process, handles file operations, persists across SSH sessions

## Issues Discovered

### 1. Shell Output Corruption

**Problem**: Shell initialization (.bashrc, .profile, MOTD) outputs text before the binary protocol starts, corrupting message parsing.

**Research**: Zed editor had same issue, fixed in PR #39451 with a sync marker approach.

**Solution**: Proxy outputs a unique marker (`REDMARGIN_SYNC_7f3d9a\n`) that client waits for. Any text before marker is discarded as shell garbage.

### 2. fork() Breaks GCD/Swift Concurrency

**Problem**: Original daemon used `fork()` to detach from terminal. But `fork()` only duplicates the calling thread - GCD dispatch queues and Swift async/await break because their worker threads don't exist in the child process.

**Symptoms**: Daemon process exists, socket created, but never responds to messages.

**Research**: This is a known POSIX limitation. Apple's documentation warns against using GCD after fork.

**Solution**: Removed `fork()` from Daemon.swift. Proxy now spawns daemon using `setsid --fork` which forks *before* Swift/GCD initializes:

```swift
// Proxy.swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
process.arguments = ["--fork", binaryPath, "run", "--pid-file", pidFile, ...]
```

### 3. Race Condition in Daemon Startup

**Problem**: Multiple SSH connections could try to start daemon simultaneously, causing conflicts.

**Solution**: Lock file with `flock()` (macOS) or `fcntl()` (Linux):

```swift
// Proxy.swift
let lockFD = acquireLock(lockFile: lockFile)
defer { releaseLock(fd: lockFD, lockFile: lockFile) }
// Only one process can start daemon
```

### 4. Sync Marker Timing (Root Cause)

**Problem**: Sync marker was output at proxy startup, BEFORE connecting to daemon. Sequence:

1. Proxy starts, outputs sync marker
2. Client sees marker, sends Hello immediately
3. Proxy still connecting to daemon (can take 10 seconds if starting)
4. Hello sits in stdin buffer, client times out

**Solution**: Move sync marker to AFTER daemon connection:

```swift
// WRONG - marker before daemon ready
static func start(reconnect: Bool) {
    print(syncMarker, terminator: "")  // Client thinks we're ready
    fflush(stdout)
    let socketFD = connectToDaemon(...)  // But we're not!
    bridgeStdioToSocket(socketFD: socketFD)
}

// CORRECT - marker after daemon ready
static func start(reconnect: Bool) {
    let socketFD = connectToDaemon(...)  // Connect first
    print(syncMarker, terminator: "")     // NOW we're ready
    fflush(stdout)
    bridgeStdioToSocket(socketFD: socketFD)
}
```

**Key insight**: The sync marker means "I am ready to receive protocol messages", not "I exist".

## Other Issues Fixed Along the Way

### Text File Busy Error

**Problem**: `zsh:1: text file busy` when trying to execute binary that's still being uploaded.

**Cause**: SCP upload not complete when SSH tries to execute binary.

**Mitigation**: Retry logic with exponential backoff.

### State Machine Corruption

**Problem**: After first failure, `send()` returns `ERROR: Not in connected/connecting state`.

**Cause**: Connection state transitions to `disconnected` before retry completes.

**Note**: This is a secondary symptom of the sync marker timing issue.

## SSH Options Used

```swift
let args = [
    "-T",                           // Disable PTY (cleaner for binary protocol)
    "-o", "BatchMode=yes",          // No interactive prompts
    "-o", "ConnectTimeout=10",      // Don't wait forever for TCP
    "-o", "ServerAliveInterval=15", // Keepalive ping every 15s
    "-o", "ServerAliveCountMax=3",  // Disconnect after 3 missed pings
    host,
    serverBinaryPath,
    "proxy", "--reconnect"
]
```

**Removed** (caused issues):
- `ControlMaster` - Stale sockets cause "Session open refused by peer"
- `ControlPath` - Tilde expansion unreliable
- `ControlPersist` - Related to above

## Client-Side Sync Marker Handling

```swift
private func waitForSyncMarker(...) async throws {
    // Use readabilityHandler for non-blocking reads
    stdout.readabilityHandler = { handle in
        let data = handle.availableData
        // Accumulate until marker found
    }

    // Poll with 10 second timeout
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if await accumulator.foundMarker { return }
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    throw SSHConnectionError.handshakeTimeout(host: host)
}
```

## Debugging Commands

```bash
# Clean slate - remove server and kill daemon
ssh dockerhost 'pkill -f redmargin-server; rm -rf ~/.redmargin-server'

# Check what's deployed
ssh dockerhost 'ls -la ~/.redmargin-server/'

# Test proxy manually (should output sync marker then wait)
ssh dockerhost ~/.redmargin-server/redmargin-server-0.42.8 proxy --reconnect

# Send Hello and see response
printf '\x00\x00\x00S{"type":"Hello","id":1,"payload":{"clientVersion":"0.42.8","capabilities":[]}}' | \
    ssh -T dockerhost ~/.redmargin-server/redmargin-server-0.42.8 proxy --reconnect | xxd

# Check if daemon is running
ssh dockerhost 'ps aux | grep redmargin'

# Check daemon socket
ssh dockerhost 'ls -la ~/.redmargin-server/rpc.sock'

# View app logs
tail -f /tmp/redmargin.log
```

### 5. connect() Succeeds Before accept() (THE REAL Root Cause)

**Problem**: Even with sync marker moved after `connectToDaemon()`, first connections still timed out. Investigation revealed that `connect()` on a Unix domain socket succeeds as soon as the connection is queued in the kernel backlog - it does NOT wait for the server to call `accept()`.

**Sequence**:
1. Proxy spawns daemon via `setsid --fork`
2. Daemon calls `listener.start()` → socket listening, but `accept()` not called yet
3. Daemon initializes `RPCHandler()` → takes some time
4. Proxy's `connect()` succeeds (connection queued in kernel)
5. Proxy outputs sync marker → client thinks daemon is ready
6. Client sends Hello → sits in kernel buffer
7. Daemon finally calls `accept()`, processes Hello → too late, client timed out

**Solution**: Two-phase ready signal:
1. Daemon sends `RDY\n` immediately after `accept()` (proves it's truly ready)
2. Proxy waits for `RDY\n` before outputting sync marker
3. Moved `RPCHandler()` initialization BEFORE `listener.start()` to minimize gap

```swift
// Daemon.swift - Send ready signal after accept()
let clientFD = listener.acceptConnection()
let readyMarker = Data("RDY\n".utf8)
readyMarker.withUnsafeBytes { ptr in
    _ = socket_write(fd: clientFD, buffer: ptr.baseAddress!, count: readyMarker.count)
}

// Proxy.swift - Wait for ready signal before sync marker
let socketFD = connectToDaemon(...)
waitForReadySignal(socketFD: socketFD)  // Blocks until "RDY\n" received
print(syncMarker, terminator: "")        // NOW client can send
```

**Key insight**: `connect()` succeeding means "kernel accepted the connection", not "server is ready to process".

## Version History

| Version | Changes |
|---------|---------|
| 0.42.3  | Initial timeout fixes |
| 0.42.4  | Added sync marker, removed fork() |
| 0.42.5  | Fixed sync marker client-side handling |
| 0.42.6  | Added lock file for daemon startup |
| 0.42.7  | Fixed setsid --fork daemon spawning |
| 0.42.8  | Moved sync marker AFTER daemon connection |
| 0.42.9  | Added RDY signal: proxy waits for daemon accept() before sync marker |
| 0.42.10 | **THE FIX**: Replaced waitUntilExit() and Thread.sleep() with usleep() |

### 6. process.waitUntilExit() Hangs with GCD (THE ACTUAL Root Cause)

**Problem**: After all the above fixes, first connections STILL failed. Used strace to trace:

```
connect() -> ECONNREFUSED
write "Daemon not running, starting..."
[spawns daemon]
[daemon starts, socket created]
[proxy NEVER makes another connect() call - stuck in GCD poll loop]
```

**Root Cause**: Swift's `Process.waitUntilExit()` hangs when used with GCD/libdispatch on Linux. Even though `setsid --fork` exits immediately (verified with `time` - 0.001s), `waitUntilExit()` never returns.

**Why**: GCD's event loop takes over and the synchronous wait interferes with libdispatch internals on Linux.

**Solution**: Replace blocking waits with `usleep()`:

```swift
// BEFORE (hangs on Linux):
try process.run()
process.waitUntilExit()

// AFTER (works):
try process.run()
usleep(100_000) // 100ms - enough for setsid to fork

// Also in connect loop:
// BEFORE: Thread.sleep(forTimeInterval: 0.1)
// AFTER: usleep(100_000)
```

**Key insight**: On Linux with Swift/GCD, avoid `Process.waitUntilExit()` and `Thread.sleep()` in synchronous code paths. Use `usleep()` instead.

## References

- [Zed PR #39451](https://github.com/zed-industries/zed/pull/39451) - Shell output handling
- [VS Code Remote SSH](https://code.visualstudio.com/docs/remote/ssh) - Connection architecture
- [Apple Threading Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/CreatingThreads/CreatingThreads.html) - fork() and threads
- [setsid(1) man page](https://man7.org/linux/man-pages/man1/setsid.1.html) - Process session leader
