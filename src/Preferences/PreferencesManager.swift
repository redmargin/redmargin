import Foundation

public enum Theme: String, CaseIterable {
    case system
    case light
    case dark
}

public enum GutterVisibility: String, CaseIterable {
    case showEmpty
    case hide
}

public enum InlineCodeColor: String, CaseIterable {
    case warm
    case cool
    case rose
    case purple
    case neutral
}

public class PreferencesManager: ObservableObject {
    public static let shared = PreferencesManager()

    private let themeKey = "RedMargin.Preferences.Theme"
    private let gutterVisibilityKey = "RedMargin.Preferences.GutterVisibilityForNonRepo"
    private let allowRemoteImagesKey = "RedMargin.Preferences.AllowRemoteImages"
    private let inlineCodeColorKey = "RedMargin.Preferences.InlineCodeColor"
    private let printMarginKey = "RedMargin.Preferences.PrintMargin"
    private let printShowGutterKey = "RedMargin.Preferences.PrintShowGutter"
    private let printShowLineNumbersKey = "RedMargin.Preferences.PrintShowLineNumbers"

    @Published public var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: themeKey) }
    }

    @Published public var gutterVisibilityForNonRepo: GutterVisibility {
        didSet { UserDefaults.standard.set(gutterVisibilityForNonRepo.rawValue, forKey: gutterVisibilityKey) }
    }

    @Published public var allowRemoteImages: Bool {
        didSet { UserDefaults.standard.set(allowRemoteImages, forKey: allowRemoteImagesKey) }
    }

    @Published public var inlineCodeColor: InlineCodeColor {
        didSet { UserDefaults.standard.set(inlineCodeColor.rawValue, forKey: inlineCodeColorKey) }
    }

    @Published public var printMargin: Double {
        didSet { UserDefaults.standard.set(printMargin, forKey: printMarginKey) }
    }

    @Published public var printShowGutter: Bool {
        didSet { UserDefaults.standard.set(printShowGutter, forKey: printShowGutterKey) }
    }

    @Published public var printShowLineNumbers: Bool {
        didSet { UserDefaults.standard.set(printShowLineNumbers, forKey: printShowLineNumbersKey) }
    }

    private init() {
        let themeString = UserDefaults.standard.string(forKey: themeKey) ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeString) ?? .system

        let defaultGutter = GutterVisibility.showEmpty.rawValue
        let gutterString = UserDefaults.standard.string(forKey: gutterVisibilityKey) ?? defaultGutter
        self.gutterVisibilityForNonRepo = GutterVisibility(rawValue: gutterString) ?? .showEmpty

        self.allowRemoteImages = UserDefaults.standard.object(forKey: allowRemoteImagesKey) as? Bool ?? false

        let colorString = UserDefaults.standard.string(forKey: inlineCodeColorKey) ?? InlineCodeColor.warm.rawValue
        self.inlineCodeColor = InlineCodeColor(rawValue: colorString) ?? .warm

        self.printMargin = UserDefaults.standard.object(forKey: printMarginKey) as? Double ?? 28

        self.printShowGutter = UserDefaults.standard.object(forKey: printShowGutterKey) as? Bool ?? true

        self.printShowLineNumbers = UserDefaults.standard.object(forKey: printShowLineNumbersKey) as? Bool ?? false
    }
}
