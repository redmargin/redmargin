import Foundation
#if canImport(os)
import os
#endif

/// Logging for the remote/SSH subsystem that is actually retrievable after the
/// fact. Plain `print()` goes to a GUI app's stdout, which is discarded, and
/// os_log `.info`/`.debug` are not persisted to disk by default, so neither
/// showed up under `log show`. These log at `.notice`/`.error`, which the macOS
/// unified log retains, so failures can be read back with:
///
///     log show --predicate 'subsystem == "com.redmargin"' --info --last 1h
///
/// On Linux (the server daemon, no `os`) it writes to stderr, which the daemon
/// already captures to its stderr log.
public enum RemoteLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.redmargin", category: "Remote")
    #endif

    /// Normal diagnostic event. Persisted at `.notice`.
    public static func info(_ message: @autoclosure () -> String) {
        let text = message()
        #if canImport(os)
        logger.notice("\(text, privacy: .public)")
        #else
        FileHandle.standardError.write(Data((text + "\n").utf8))
        #endif
    }

    /// Failure or unexpected condition. Persisted at `.error`.
    public static func error(_ message: @autoclosure () -> String) {
        let text = message()
        #if canImport(os)
        logger.error("\(text, privacy: .public)")
        #else
        FileHandle.standardError.write(Data((text + "\n").utf8))
        #endif
    }
}
