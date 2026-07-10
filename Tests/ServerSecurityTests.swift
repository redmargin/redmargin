import XCTest
@testable import RedmarginCore
@testable import redmargin_server

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The helper's RPC socket is unauthenticated and its asset reads are driven by
/// paths that appear inside a Markdown document. These cover both boundaries.
final class ServerSecurityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: "/tmp/rm-sec-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private struct FifoUnavailable: Error, CustomStringConvertible {
        let errorNumber: Int32
        var description: String { "mkfifo() failed: errno \(errorNumber)" }
    }

    /// A FIFO is the only way to present a non-regular file to these reads. If the
    /// platform cannot make one the test has not run, so it must not report success.
    private func makeFifo(at url: URL) throws {
        guard mkfifo(url.path, 0o600) == 0 else {
            throw FifoUnavailable(errorNumber: errno)
        }
    }

    // MARK: - Document reads

    func testReadFileReturnsRegularFile() async throws {
        let doc = tempDir.appendingPathComponent("note.md")
        try "# Title\n".write(to: doc, atomically: true, encoding: .utf8)

        let response = await FileOperations().readFile(path: doc.path)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.content, "# Title\n")
    }

    /// A document path arrives from the client. Pointing it at a FIFO would park
    /// the actor on an open() that never returns, wedging the whole connection.
    func testReadFileRejectsNonRegularFile() async throws {
        let fifo = tempDir.appendingPathComponent("pipe.md")
        try makeFifo(at: fifo)

        let response = await FileOperations().readFile(path: fifo.path)

        XCTAssertNil(response.content)
        XCTAssertEqual(response.error, "Not a regular file")
    }

    /// Oversized documents are refused from the stat, before any bytes are loaded.
    func testReadFileRejectsOversizedFile() async throws {
        let doc = tempDir.appendingPathComponent("huge.md")
        FileManager.default.createFile(atPath: doc.path, contents: nil)
        let handle = try FileHandle(forWritingTo: doc)
        // Sparse: costs no disk, but reports a size past the limit.
        try handle.truncate(atOffset: UInt64(FileOperations.maxDocumentBytes) + 1)
        try handle.close()

        let response = await FileOperations().readFile(path: doc.path)

        XCTAssertNil(response.content)
        XCTAssertEqual(response.error, "File exceeds \(FileOperations.maxDocumentBytes) bytes")
    }

    /// A symlink to a FIFO must be judged by its target, not by the link.
    func testReadFileRejectsSymlinkToNonRegularFile() async throws {
        let fifo = tempDir.appendingPathComponent("pipe")
        try makeFifo(at: fifo)
        let link = tempDir.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fifo)

        let response = await FileOperations().readFile(path: link.path)

        XCTAssertNil(response.content)
        XCTAssertEqual(response.error, "Not a regular file")
    }

    func testReadFileReportsMissingFile() async throws {
        let response = await FileOperations().readFile(path: tempDir.appendingPathComponent("absent.md").path)

        XCTAssertNil(response.content)
        XCTAssertEqual(response.errorCode, FileErrorCode.fileNotFound.rawValue)
    }

    // MARK: - Asset reads

    func testReadAssetReturnsRegularFile() async throws {
        let asset = tempDir.appendingPathComponent("image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: asset)

        let response = await FileOperations().readAsset(path: asset.path)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.mimeType, "image/png")
        XCTAssertEqual(response.data, Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())
    }

    /// A Markdown image pointing at a FIFO would otherwise park the actor on an
    /// open() that never returns, wedging every later request on the connection.
    func testReadAssetRejectsNonRegularFile() async throws {
        let fifo = tempDir.appendingPathComponent("pipe.png")
        try makeFifo(at: fifo)

        let response = await FileOperations().readAsset(path: fifo.path)

        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "Not a regular file")
    }

    /// Oversized assets are refused from the stat, before any bytes are loaded.
    func testReadAssetRejectsOversizedFile() async throws {
        let asset = tempDir.appendingPathComponent("huge.png")
        FileManager.default.createFile(atPath: asset.path, contents: nil)
        let handle = try FileHandle(forWritingTo: asset)
        // Sparse: costs no disk, but reports a size past the limit.
        try handle.truncate(atOffset: UInt64(FileOperations.maxAssetBytes) + 1)
        try handle.close()

        let response = await FileOperations().readAsset(path: asset.path)

        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "Asset exceeds \(FileOperations.maxAssetBytes) bytes")
    }

    func testReadAssetAcceptsFileAtTheSizeLimit() async throws {
        let asset = tempDir.appendingPathComponent("limit.png")
        FileManager.default.createFile(atPath: asset.path, contents: nil)
        let handle = try FileHandle(forWritingTo: asset)
        try handle.truncate(atOffset: UInt64(FileOperations.maxAssetBytes))
        try handle.close()

        let response = await FileOperations().readAsset(path: asset.path)

        XCTAssertNil(response.error)
        XCTAssertNotNil(response.data)
    }

    /// A symlink to a regular file is fine; the checks describe the resolved target.
    func testReadAssetFollowsSymlinkToRegularFile() async throws {
        let target = tempDir.appendingPathComponent("target.png")
        try Data([0x01, 0x02]).write(to: target)
        let link = tempDir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let response = await FileOperations().readAsset(path: link.path)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.data, Data([0x01, 0x02]).base64EncodedString())
    }

    /// A symlink whose target is a FIFO must be rejected on the target's type,
    /// not accepted because the link itself looks ordinary.
    func testReadAssetRejectsSymlinkToNonRegularFile() async throws {
        let fifo = tempDir.appendingPathComponent("pipe")
        try makeFifo(at: fifo)
        let link = tempDir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fifo)

        let response = await FileOperations().readAsset(path: link.path)

        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "Not a regular file")
    }

    func testReadAssetReportsMissingFile() async throws {
        let response = await FileOperations().readAsset(path: tempDir.appendingPathComponent("absent.png").path)

        XCTAssertNil(response.data)
        XCTAssertEqual(response.error, "File not found")
    }

    // MARK: - Socket permissions

    /// Anyone who can connect to this socket issues unauthenticated file RPCs as
    /// the owning account, so it must never be readable by group or other,
    /// whatever umask the login shell happens to set.
    func testListenerSocketIsOwnerOnly() throws {
        let permissiveMask = umask(0o000)
        defer { _ = umask(permissiveMask) }

        let socketPath = tempDir.appendingPathComponent("rpc.sock").path
        let listener = UnixSocketListener(path: socketPath)
        try listener.start()
        defer { listener.close() }

        let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)
        let mode = try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.int16Value)
        XCTAssertEqual(mode, 0o600, "RPC socket is reachable by other local users")
    }
}
