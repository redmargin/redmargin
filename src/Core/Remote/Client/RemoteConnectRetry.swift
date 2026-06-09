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
