import XCTest

class BaseUITest: XCTestCase {
    var app: XCUIApplication!

    /// Real user home directory - hardcoded to avoid sandbox issues
    /// The uitest.sh script runs outside the sandbox and creates the test directory
    static let realHomeDir = "/Users/marco"

    /// Test directory
    static let testDir = "\(realHomeDir)/RedmarginUITests-Temp"
    static let testFilePath = "\(testDir)/test.md"

    /// Downloads directory
    static let downloadsDir = "\(realHomeDir)/Downloads"

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Quit any existing instance first
        let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.redmargin.app"
        ).first
        runningApp?.terminate()
        sleep(2)

        // Open the test file using the open command (runs in a separate process, bypasses sandbox)
        // We use osascript to run the open command because Process is sandboxed
        let script = """
            do shell script "open -a Redmargin '\(Self.testFilePath)'"
        """
        let appleScript = NSAppleScript(source: script)
        var errorInfo: NSDictionary?
        appleScript?.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            print("AppleScript error: \(error)")
        }

        // Wait for app to launch
        sleep(3)

        // Connect to the app
        app = XCUIApplication(bundleIdentifier: "com.redmargin.app")

        // Wait for app window to be ready
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "App window should exist")

        // Give the app time to fully render the content
        sleep(2)
    }

    override func tearDownWithError() throws {
        // Terminate app
        app.terminate()
    }

    /// Export to PDF via Cmd+E
    func exportToPDF() {
        pressCharKey("e", modifiers: .command)
        sleep(3) // Wait for export to complete
    }
}
