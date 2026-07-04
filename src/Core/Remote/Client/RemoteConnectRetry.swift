import Foundation

/// Retry policy for establishing a remote connection.
///
/// Hard-unreachable failures (no route, refused, auth) never self-heal and must
/// not be retried; transient failures (timeouts, dropped handshakes) retry with
/// full-jitter exponential backoff, capped at a small number of attempts. The
/// pieces are pure and closure-driven so the policy can be tested without any
/// live connection.
public enum RemoteConnectRetry {
    /// Total attempts (including the first) before giving up on a transient error.
    public static let maxAttempts = 3

    /// Upper bound on a single backoff delay, in seconds (2^3).
    public static let maxBackoffDelay: TimeInterval = 8

    /// Whether a connect failure is worth retrying. Errors that mean the host is
    /// not reachable right now are terminal (fast-fail so a dead host does not stall
    /// reopening); only errors that occur after SSH has reached the host — a wedged
    /// helper or a transient mid-session drop — are retryable. A `.connectionTimeout`
    /// (could not even establish SSH) is terminal: retrying just burns more 5s
    /// timeouts on an unreachable host.
    public static func isRetryable(_ error: SSHConnectionError) -> Bool {
        switch error {
        case .operationTimeout, .handshakeTimeout, .serverNotResponding,
             .helperStartupTimeout, .unexpectedDisconnect:
            return true
        case .hostUnreachable, .connectionRefused, .authenticationFailed,
             .connectionTimeout, .sshProcessFailed:
            return false
        }
    }

    /// Attempts (post-increment) before killing a possibly-wedged remote daemon.
    public static let killDaemonAfterAttempts = 3

    /// Attempts (post-increment) before redeploying the remote server binary.
    public static let redeployAfterAttempts = 6

    /// Corrective action a failing reconnect loop should take before its next
    /// attempt. A bare `proxy --reconnect` cannot recover on its own from two
    /// states, so the loop must escalate rather than retry the same doomed
    /// command forever:
    ///
    /// - `.killDaemon` — a wedged-but-present daemon; killing it lets the next
    ///   SSH session start a clean one. Cheap, so try it first.
    /// - `.redeploy` — the versioned binary is missing or stale, e.g. version
    ///   skew right after an app update, when reconnect targets a
    ///   `redmargin-server-<newversion>` path the host has never had. No number
    ///   of bare reconnects can fix this; only laying the binary down can.
    ///
    /// Callers reset their attempt counter after a `.redeploy` so backoff (and
    /// this schedule) restart from scratch.
    public enum ReconnectEscalation: Equatable {
        case none
        case killDaemon
        case redeploy
    }

    public static func escalation(forAttempt attempt: Int) -> ReconnectEscalation {
        if attempt >= redeployAfterAttempts { return .redeploy }
        if attempt == killDaemonAfterAttempts { return .killDaemon }
        return .none
    }

    /// Whether a background reconnect loop should stop and park in `.disconnected`
    /// rather than keep retrying. True for failures a reconnect can never fix on
    /// its own — auth denied, connection refused, host unreachable — so the loop
    /// does not hammer a host that will not recover without user action or the
    /// network coming back (a user focus/refresh or wake-from-sleep re-arms it).
    ///
    /// `sshProcessFailed` is deliberately excluded: it is how a missing or stale
    /// binary surfaces ("no such file"), which the redeploy escalation fixes, so
    /// the loop must keep going long enough to reach that escalation.
    public static func reconnectShouldGiveUp(_ error: SSHConnectionError) -> Bool {
        switch error {
        case .authenticationFailed, .connectionRefused, .hostUnreachable, .connectionTimeout:
            return true
        case .sshProcessFailed, .operationTimeout, .handshakeTimeout,
             .serverNotResponding, .helperStartupTimeout, .unexpectedDisconnect:
            return false
        }
    }

    /// Full-jitter backoff: a delay drawn uniformly from `0...min(maxDelay, 2^attempt)`.
    /// `randomFraction` (clamped to `0...1`) makes the draw deterministic for tests.
    public static func backoffDelay(
        attempt: Int,
        maxDelay: TimeInterval = maxBackoffDelay,
        randomFraction: Double
    ) -> TimeInterval {
        let ceiling = min(maxDelay, pow(2.0, Double(attempt)))
        let fraction = min(max(randomFraction, 0), 1)
        return fraction * ceiling
    }

    /// Runs `operation`, retrying transient `SSHConnectionError`s with full-jitter
    /// backoff up to `maxAttempts`. Non-retryable errors (and non-SSH errors)
    /// rethrow immediately. `sleep` and `randomFraction` are injectable so the
    /// loop runs deterministically and instantly under test.
    public static func run(
        maxAttempts: Int = RemoteConnectRetry.maxAttempts,
        randomFraction: @escaping () -> Double = { Double.random(in: 0...1) },
        sleep: (TimeInterval) async -> Void = { delay in
            _ = try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        },
        operation: () async throws -> Void
    ) async throws {
        var attempt = 0
        while true {
            do {
                try await operation()
                return
            } catch let error as SSHConnectionError {
                attempt += 1
                guard isRetryable(error), attempt < maxAttempts else { throw error }
                await sleep(backoffDelay(attempt: attempt, randomFraction: randomFraction()))
            }
        }
    }
}
