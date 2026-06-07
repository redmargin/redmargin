import XCTest
import Foundation
@testable import RedmarginCore

final class RemoteConnectRetryPolicyTests: XCTestCase {
    func testHostNotReachableErrorsAreNotRetryable() {
        XCTAssertFalse(RemoteConnectRetry.isRetryable(.hostUnreachable(host: "h")))
        XCTAssertFalse(RemoteConnectRetry.isRetryable(.connectionRefused(host: "h")))
        XCTAssertFalse(RemoteConnectRetry.isRetryable(.authenticationFailed(host: "h")))
        // A connection timeout means SSH could not reach the host; retrying just
        // burns more timeouts, so it is terminal too (fast-fail on a dead host).
        XCTAssertFalse(RemoteConnectRetry.isRetryable(.connectionTimeout(host: "h")))
    }

    func testTransientErrorsAreRetryable() {
        XCTAssertTrue(RemoteConnectRetry.isRetryable(.operationTimeout(operation: "read")))
        XCTAssertTrue(RemoteConnectRetry.isRetryable(.handshakeTimeout(host: "h")))
        XCTAssertTrue(RemoteConnectRetry.isRetryable(.serverNotResponding(host: "h")))
        XCTAssertTrue(RemoteConnectRetry.isRetryable(.helperStartupTimeout(host: "h", stderr: "")))
        XCTAssertTrue(RemoteConnectRetry.isRetryable(.unexpectedDisconnect))
    }

    func testBackoffWithJitterStaysWithinBounds() {
        for attempt in 0...5 {
            let ceiling = min(RemoteConnectRetry.maxBackoffDelay, pow(2.0, Double(attempt)))
            for fraction in [0.0, 0.25, 0.5, 0.99, 1.0] {
                let delay = RemoteConnectRetry.backoffDelay(attempt: attempt, randomFraction: fraction)
                XCTAssertGreaterThanOrEqual(delay, 0)
                XCTAssertLessThanOrEqual(delay, ceiling)
            }
            // Out-of-range fractions are clamped, not extrapolated.
            XCTAssertEqual(RemoteConnectRetry.backoffDelay(attempt: attempt, randomFraction: 2.0), ceiling)
            XCTAssertEqual(RemoteConnectRetry.backoffDelay(attempt: attempt, randomFraction: -1.0), 0)
        }
        XCTAssertEqual(RemoteConnectRetry.maxAttempts, 3)
    }

    func testRetryLoopCapsAtThreeAttempts() async {
        var attempts = 0
        do {
            try await RemoteConnectRetry.run(randomFraction: { 0 }, sleep: { _ in }) {
                attempts += 1
                throw SSHConnectionError.serverNotResponding(host: "h")  // always retryable
            }
            XCTFail("Should have thrown after exhausting retries")
        } catch {
            XCTAssertEqual(attempts, 3, "Operation runs at most three times")
        }
    }

    func testRetryLoopRetriesTransientThenSucceeds() async throws {
        var attempts = 0
        try await RemoteConnectRetry.run(randomFraction: { 0 }, sleep: { _ in }) {
            attempts += 1
            if attempts == 1 { throw SSHConnectionError.operationTimeout(operation: "connect") }
        }
        XCTAssertEqual(attempts, 2, "One transient failure then success, within the cap")
    }

    func testRetryLoopDoesNotRetryHardUnreachable() async {
        var attempts = 0
        do {
            try await RemoteConnectRetry.run(randomFraction: { 0 }, sleep: { _ in }) {
                attempts += 1
                throw SSHConnectionError.hostUnreachable(host: "h")
            }
            XCTFail("Hard-unreachable should rethrow immediately")
        } catch {
            XCTAssertEqual(attempts, 1, "Hard-unreachable must not retry")
        }
    }

    func testServerDeployerClassifiesUnreachableStderr() {
        assertCase(parseSSHStderr("ssh: connect to host x port 22: No route to host", host: "h"),
                   matches: "hostUnreachable")
        assertCase(parseSSHStderr("ssh: connect to host x: Network is unreachable", host: "h"),
                   matches: "hostUnreachable")
        assertCase(parseSSHStderr("ssh: connect to host x port 22: Connection refused", host: "h"),
                   matches: "connectionRefused")
        assertCase(parseSSHStderr("Permission denied (publickey).", host: "h"),
                   matches: "authenticationFailed")
    }

    private func assertCase(
        _ error: SSHConnectionError,
        matches expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual: String
        switch error {
        case .hostUnreachable: actual = "hostUnreachable"
        case .connectionRefused: actual = "connectionRefused"
        case .authenticationFailed: actual = "authenticationFailed"
        case .connectionTimeout: actual = "connectionTimeout"
        case .sshProcessFailed: actual = "sshProcessFailed"
        default: actual = "other"
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}
