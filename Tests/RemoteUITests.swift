import XCTest
@testable import RedmarginCore

final class RemoteConnectionParserTests: XCTestCase {

    // MARK: - Valid Connection Strings

    func testParseUserAtHostWithPath() {
        let result = RemoteConnectionParser.parse("marco@devtest:/home/marco/docs/readme.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "marco@devtest")
        XCTAssertEqual(result?.path, "/home/marco/docs/readme.md")
    }

    func testParseHostOnlyWithPath() {
        let result = RemoteConnectionParser.parse("devtest:/var/log/app.log")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "devtest")
        XCTAssertEqual(result?.path, "/var/log/app.log")
    }

    func testParseFullHostnameWithUser() {
        let result = RemoteConnectionParser.parse("admin@server.example.com:/etc/nginx/nginx.conf")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "admin@server.example.com")
        XCTAssertEqual(result?.path, "/etc/nginx/nginx.conf")
    }

    func testParseIPAddressWithUser() {
        let result = RemoteConnectionParser.parse("root@192.168.1.100:/home/user/file.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "root@192.168.1.100")
        XCTAssertEqual(result?.path, "/home/user/file.md")
    }

    func testParseRootPath() {
        let result = RemoteConnectionParser.parse("server:/file.txt")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "server")
        XCTAssertEqual(result?.path, "/file.txt")
    }

    func testParseTrimmedWhitespace() {
        let result = RemoteConnectionParser.parse("  user@host:/path/file.md  ")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "user@host")
        XCTAssertEqual(result?.path, "/path/file.md")
    }

    func testParsePathWithSpaces() {
        let result = RemoteConnectionParser.parse("server:/path/with spaces/file.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "server")
        XCTAssertEqual(result?.path, "/path/with spaces/file.md")
    }

    func testParseDeepPath() {
        let result = RemoteConnectionParser.parse("host:/a/b/c/d/e/f/g/h/file.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "host")
        XCTAssertEqual(result?.path, "/a/b/c/d/e/f/g/h/file.md")
    }

    // MARK: - Invalid Connection Strings

    func testParseEmptyString() {
        let result = RemoteConnectionParser.parse("")
        XCTAssertNil(result)
    }

    func testParseWhitespaceOnly() {
        let result = RemoteConnectionParser.parse("   ")
        XCTAssertNil(result)
    }

    func testParseMissingPath() {
        let result = RemoteConnectionParser.parse("user@host:")
        XCTAssertNil(result)
    }

    func testParseMissingHost() {
        let result = RemoteConnectionParser.parse(":/path/file.md")
        XCTAssertNil(result)
    }

    func testParseRelativePath() {
        let result = RemoteConnectionParser.parse("host:relative/path.md")
        XCTAssertNil(result)
    }

    func testParseNoColon() {
        let result = RemoteConnectionParser.parse("user@host/path/file.md")
        XCTAssertNil(result)
    }

    func testParseHostWithSpacesNoUser() {
        // Hosts without @ should not contain spaces
        let result = RemoteConnectionParser.parse("my server:/path/file.md")
        XCTAssertNil(result)
    }

    func testParseOnlyColon() {
        let result = RemoteConnectionParser.parse(":")
        XCTAssertNil(result)
    }

    func testParseColonAtEnd() {
        let result = RemoteConnectionParser.parse("host:")
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testParsePathWithColons() {
        // Path containing colons should work (uses last colon as separator)
        let result = RemoteConnectionParser.parse("host:/path/with:colons/file.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "host")
        XCTAssertEqual(result?.path, "/path/with:colons/file.md")
    }

    func testParseHostWithPort() {
        // This is technically valid - user could have this as an alias
        let result = RemoteConnectionParser.parse("host:/path.md")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "host")
        XCTAssertEqual(result?.path, "/path.md")
    }

    func testParsedConnectionEquality() {
        let conn1 = RemoteConnectionParser.ParsedConnection(host: "host", path: "/path")
        let conn2 = RemoteConnectionParser.ParsedConnection(host: "host", path: "/path")
        let conn3 = RemoteConnectionParser.ParsedConnection(host: "host", path: "/other")

        XCTAssertEqual(conn1, conn2)
        XCTAssertNotEqual(conn1, conn3)
    }
}

final class RemoteLocationTests: XCTestCase {

    func testDisplayString() {
        let location = RemoteLocation(host: "user@server", path: "/home/user/file.md")
        XCTAssertEqual(location.displayString, "user@server:/home/user/file.md")
    }

    func testDisplayTitle() {
        let location = RemoteLocation(host: "user@server", path: "/home/user/docs/readme.md")
        XCTAssertEqual(location.displayTitle, "[remote] readme.md")
    }

    func testDisplayTitleRootFile() {
        let location = RemoteLocation(host: "host", path: "/file.md")
        XCTAssertEqual(location.displayTitle, "[remote] file.md")
    }

    func testHashable() {
        let loc1 = RemoteLocation(host: "host", path: "/path")
        let loc2 = RemoteLocation(host: "host", path: "/path")
        let loc3 = RemoteLocation(host: "host", path: "/other")

        var set = Set<RemoteLocation>()
        set.insert(loc1)
        set.insert(loc2)

        XCTAssertEqual(set.count, 1)

        set.insert(loc3)
        XCTAssertEqual(set.count, 2)
    }

    func testCodable() throws {
        let location = RemoteLocation(host: "user@host", path: "/path/to/file.md")

        let encoded = try JSONEncoder().encode(location)
        let decoded = try JSONDecoder().decode(RemoteLocation.self, from: encoded)

        XCTAssertEqual(location, decoded)
    }
}

final class RedmarginLaunchRequestTests: XCTestCase {
    func testParseLaunchURL() throws {
        let url = try XCTUnwrap(URL(string: "redmargin://open?host=devtest&path=/home/marco/readme.md&kind=file"))
        let request = try XCTUnwrap(RedmarginLaunchRequest.parse(url))

        XCTAssertEqual(request.host, "devtest")
        XCTAssertEqual(request.path, "/home/marco/readme.md")
        XCTAssertEqual(request.kind, .file)
    }

    func testParseLaunchURLWithEncodedValues() throws {
        var components = URLComponents()
        components.scheme = "redmargin"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "host", value: "marco@dev vm"),
            URLQueryItem(name: "path", value: "/home/marco/docs/a file.md"),
            URLQueryItem(name: "kind", value: "folder")
        ]

        let request = try XCTUnwrap(components.url.flatMap(RedmarginLaunchRequest.parse))
        XCTAssertEqual(request.host, "marco@dev vm")
        XCTAssertEqual(request.path, "/home/marco/docs/a file.md")
        XCTAssertEqual(request.kind, .folder)
    }

    func testRejectsNonRedmarginURL() throws {
        let url = try XCTUnwrap(URL(string: "file:///tmp/readme.md"))
        XCTAssertNil(RedmarginLaunchRequest.parse(url))
    }

    func testBuildsRoundTrippableURL() throws {
        let original = RedmarginLaunchRequest(host: "devtest", path: "/tmp/readme.md", kind: .file)
        let parsed = try XCTUnwrap(original.url.flatMap(RedmarginLaunchRequest.parse))
        XCTAssertEqual(parsed, original)
    }
}
