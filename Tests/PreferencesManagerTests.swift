import XCTest
import AppKit
import SwiftUI
@testable import RedmarginLib

final class PreferencesManagerTests: XCTestCase {
    private let testKeys = [
        "RedMargin.Preferences.Theme",
        "RedMargin.Preferences.ShowGutter",
        "RedMargin.Preferences.ShowLineNumbers",
        "RedMargin.Preferences.ShowGitIndicators",
        "RedMargin.Preferences.AllowRemoteImages",
        "RedMargin.Preferences.InlineCodeColor",
        "RedMargin.Preferences.PrintTopMargin",
        "RedMargin.Preferences.PrintRightMargin",
        "RedMargin.Preferences.PrintBottomMargin",
        "RedMargin.Preferences.PrintLeftMargin",
        "RedMargin.Preferences.PrintFontSize"
    ]

    override func tearDown() {
        // Clean up UserDefaults after each test
        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testDefaultValues() {
        // Clear any existing values
        for key in testKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        let prefs = PreferencesManager.shared

        XCTAssertEqual(prefs.theme, .system, "Default theme should be system")
        XCTAssertEqual(prefs.showGutter, true, "Default showGutter should be true")
        XCTAssertEqual(prefs.showLineNumbers, false, "Default showLineNumbers should be false")
        XCTAssertEqual(prefs.showGitIndicators, true, "Default showGitIndicators should be true")
        XCTAssertEqual(prefs.allowRemoteImages, false, "Default allowRemoteImages should be false")
        XCTAssertEqual(prefs.inlineCodeColor, .warm, "Default inline code color should be warm")
    }

    func testThemePersists() {
        let prefs = PreferencesManager.shared
        prefs.theme = .dark

        // Verify it was saved to UserDefaults
        let saved = UserDefaults.standard.string(forKey: "RedMargin.Preferences.Theme")
        XCTAssertEqual(saved, "dark", "Theme should persist to UserDefaults")
    }

    func testRemoteImagesPersists() {
        let prefs = PreferencesManager.shared
        prefs.allowRemoteImages = true

        // Verify it was saved to UserDefaults
        let saved = UserDefaults.standard.bool(forKey: "RedMargin.Preferences.AllowRemoteImages")
        XCTAssertEqual(saved, true, "Allow remote images should persist to UserDefaults")
    }

    func testGutterPreferencesPersist() {
        let prefs = PreferencesManager.shared

        prefs.showGutter = false
        XCTAssertEqual(
            UserDefaults.standard.bool(forKey: "RedMargin.Preferences.ShowGutter"),
            false,
            "showGutter should persist to UserDefaults"
        )

        prefs.showLineNumbers = true
        XCTAssertEqual(
            UserDefaults.standard.bool(forKey: "RedMargin.Preferences.ShowLineNumbers"),
            true,
            "showLineNumbers should persist to UserDefaults"
        )

        prefs.showGitIndicators = false
        XCTAssertEqual(
            UserDefaults.standard.bool(forKey: "RedMargin.Preferences.ShowGitIndicators"),
            false,
            "showGitIndicators should persist to UserDefaults"
        )
    }

    func testInlineCodeColorPersists() {
        let prefs = PreferencesManager.shared
        prefs.inlineCodeColor = .purple

        // Verify it was saved to UserDefaults
        let saved = UserDefaults.standard.string(forKey: "RedMargin.Preferences.InlineCodeColor")
        XCTAssertEqual(saved, "purple", "Inline code color should persist to UserDefaults")
    }

    func testShowHiddenFilesDefaultsFalse() {
        // Reset singleton and UserDefaults
        let prefs = PreferencesManager.shared
        prefs.showHiddenFiles = false
        UserDefaults.standard.removeObject(forKey: "RedMargin.Preferences.ShowHiddenFiles")
        XCTAssertEqual(prefs.showHiddenFiles, false, "Default showHiddenFiles should be false")
    }

    func testShowHiddenFilesPersists() {
        let prefs = PreferencesManager.shared
        prefs.showHiddenFiles = true

        let saved = UserDefaults.standard.bool(forKey: "RedMargin.Preferences.ShowHiddenFiles")
        XCTAssertEqual(saved, true, "showHiddenFiles should persist to UserDefaults")

        // Reset
        prefs.showHiddenFiles = false
    }

    func testPrintFontSizePersists() {
        let prefs = PreferencesManager.shared
        prefs.printFontSize = 12

        let saved = UserDefaults.standard.double(forKey: "RedMargin.Preferences.PrintFontSize")
        XCTAssertEqual(saved, 12, "printFontSize should persist to UserDefaults")

        // Reset
        prefs.printFontSize = 15
    }

    func testPrintMarginsPersist() {
        let prefs = PreferencesManager.shared
        prefs.printTopMargin = 12
        prefs.printRightMargin = 24
        prefs.printBottomMargin = 36
        prefs.printLeftMargin = 48

        XCTAssertEqual(UserDefaults.standard.double(forKey: "RedMargin.Preferences.PrintTopMargin"), 12)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "RedMargin.Preferences.PrintRightMargin"), 24)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "RedMargin.Preferences.PrintBottomMargin"), 36)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "RedMargin.Preferences.PrintLeftMargin"), 48)
        XCTAssertEqual(
            prefs.printMargins,
            PrintMargins(top: 12, right: 24, bottom: 36, left: 48),
            "printMargins should combine all persisted margin fields"
        )

        // Reset
        prefs.printTopMargin = 56
        prefs.printRightMargin = 28
        prefs.printBottomMargin = 56
        prefs.printLeftMargin = 28
    }

    func testNumberTextFieldCommitsValueBeforeTabbing() {
        var value = 10.0
        let binding = Binding<Double>(
            get: { value },
            set: { value = $0 }
        )
        let numberField = NumberTextField(value: binding, range: 0...144, step: 1)
        let coordinator = numberField.makeCoordinator()
        let textField = NSTextField()
        textField.stringValue = "42"

        let handled = coordinator.control(
            textField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertTab(_:))
        )

        XCTAssertTrue(handled, "Tab should be handled by the number field")
        XCTAssertEqual(value, 42, "Tabbing away should commit the edited value")
    }
}
