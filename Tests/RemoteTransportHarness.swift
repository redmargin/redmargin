import XCTest
import Foundation
@testable import RedmarginCore

/// Drives a real `SSHConnection` over a pipe instead of an ssh process, so a test
/// can decide exactly when each remote request is answered.
///
/// Nothing about the connection is stubbed: its framing, request registration,
/// and response routing are the production paths. Only the peer on the far end of
/// the pipe is ours, which is what makes an "older read finishes last" ordering
/// reproducible instead of timing-dependent.
final class FakeRemoteHost: @unchecked Sendable {
    let connection: SSHConnection

    private let pipe = Pipe()
    private let streamHandler = RPCStreamHandler()
    private let lock = NSLock()

    /// Contents served for `ReadFile`, keyed by path.
    private var files: [String: String] = [:]
    /// Extra latency before answering `ReadFile` for a path.
    private var readDelays: [String: TimeInterval] = [:]
    /// Extra latency before answering `WriteFile` for a path.
    private var writeDelays: [String: TimeInterval] = [:]
    /// Every `WriteFile` the client issued, in order.
    private var writes: [(path: String, content: String)] = []
    /// When false the host receives requests but never answers, standing in for a
    /// helper that has stopped responding.
    private var answersRequests = true
    /// Every request type the client sent, in order.
    private var requests: [String] = []

    init() async {
        connection = SSHConnection(host: "harness.invalid")
        await connection.configureForTesting(stdin: pipe)
        startServing()
    }

    // MARK: - Test configuration

    func setFile(_ path: String, contents: String, readDelay: TimeInterval = 0, writeDelay: TimeInterval = 0) {
        lock.lock()
        files[path] = contents
        if readDelay > 0 { readDelays[path] = readDelay }
        if writeDelay > 0 { writeDelays[path] = writeDelay }
        lock.unlock()
    }

    /// Stops answering, as a wedged helper would.
    func goSilent() {
        lock.lock()
        answersRequests = false
        lock.unlock()
    }

    var recordedWrites: [(path: String, content: String)] {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    var recordedRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func contents(of path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return files[path]
    }

    // MARK: - Serving

    private func startServing() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for frame in self.streamHandler.receive(data: data) {
                self.serve(frame)
            }
        }
    }

    private func serve(_ frame: Data) {
        guard let header = try? JSONDecoder().decode(RPCHeader.self, from: frame),
              let id = header.id,
              let type = RPCMessageType(rawValue: header.type) else { return }

        lock.lock()
        requests.append(header.type)
        let willAnswer = answersRequests
        lock.unlock()
        guard willAnswer else { return }

        switch type {
        case .hello:
            respond(id: id, type: .helloResponse,
                    payload: HelloResponsePayload(serverVersion: "harness", protocolVersion: 1, accepted: true))

        case .readFile:
            let path = decode(ReadFilePayload.self, from: frame)?.path ?? ""
            lock.lock()
            let contents = files[path]
            let delay = readDelays[path] ?? 0
            lock.unlock()

            let reply: () -> Void = { [weak self] in
                guard let self else { return }
                if let contents {
                    self.respond(id: id, type: .readFileResponse,
                                 payload: ReadFileResponsePayload(content: contents, error: nil))
                } else {
                    self.respond(id: id, type: .readFileResponse,
                                 payload: ReadFileResponsePayload(
                                    content: nil,
                                    error: "File not found",
                                    errorCode: FileErrorCode.fileNotFound.rawValue))
                }
            }
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: reply)
            } else {
                reply()
            }

        case .writeFile:
            var delay: TimeInterval = 0
            if let request = decode(WriteFilePayload.self, from: frame) {
                lock.lock()
                writes.append((path: request.path, content: request.content))
                files[request.path] = request.content
                delay = writeDelays[request.path] ?? 0
                lock.unlock()
            }
            let reply: () -> Void = { [weak self] in
                self?.respond(id: id, type: .writeFileResponse, payload: WriteFileResponsePayload(error: nil))
            }
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: reply)
            } else {
                reply()
            }

        case .watchFile:
            respond(id: id, type: .watchFileResponse, payload: WatchFileResponsePayload(token: UUID().uuidString))

        case .unwatchFile:
            respond(id: id, type: .unwatchFileResponse, payload: UnwatchFileResponsePayload(success: true))

        case .gitDetectRepo:
            // Not a repository, so no diff work follows.
            respond(id: id, type: .gitDetectRepoResponse, payload: GitDetectRepoResponsePayload(repoRoot: nil))

        default:
            break
        }
    }

    private func decode<T: Codable>(_ type: T.Type, from frame: Data) -> T? {
        try? JSONDecoder().decode(RPCMessage<T>.self, from: frame).payload
    }

    private func respond(id: Int, type: RPCMessageType, payload: some Codable) {
        guard let frame = try? RPCStreamHandler.encode(id: id, type: type.rawValue, payload: payload) else { return }
        let connection = self.connection
        Task { await connection.processIncomingData(frame) }
    }

    /// Delivers a push event (no request id) to every subscriber.
    func pushFileChanged(path: String) async {
        guard let frame = try? RPCStreamHandler.encode(
            id: nil,
            type: RPCMessageType.fileChanged.rawValue,
            payload: FileChangedPayload(path: path, changeType: "modified")
        ) else { return }
        await connection.processIncomingData(frame)
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
    }
}
