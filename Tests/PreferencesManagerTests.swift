import XCTest
@testable import RedmarginLib

final class PreferencesManagerTests: XCTestCase {
    private let testKeys = [
        "RedMargin.Preferences.Theme",
        "RedMargin.Preferences.GutterVisibilityForNonRepo",
        "RedMargin.Preferences.AllowRemoteImages",
        "RedMargin.Preferences.InlineCodeColor"
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
        XCTAssertEqual(prefs.gutterVisibilityForNonRepo, .showEmpty, "Default gutter visibility should be showEmpty")
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

    func testGutterPreferencePersists() {
        let prefs = PreferencesManager.shared
        prefs.gutterVisibilityForNonRepo = .hide

        // Verify it was saved to UserDefaults
        let saved = UserDefaults.standard.string(forKey: "RedMargin.Preferences.GutterVisibilityForNonRepo")
        XCTAssertEqual(saved, "hide", "Gutter visibility should persist to UserDefaults")
    }

    func testInlineCodeColorPersists() {
        let prefs = PreferencesManager.shared
        prefs.inlineCodeColor = .purple

        // Verify it was saved to UserDefaults
        let saved = UserDefaults.standard.string(forKey: "RedMargin.Preferences.InlineCodeColor")
        XCTAssertEqual(saved, "purple", "Inline code color should persist to UserDefaults")
    }
}
