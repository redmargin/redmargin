import Foundation

public enum Theme: String, CaseIterable {
    case system
    case light
    case dark
}

public enum InlineCodeColor: String, CaseIterable {
    case warm
    case cool
    case rose
    case purple
    case neutral
}

public enum TextWidth: String, CaseIterable {
    case narrow
    case medium
    case wide
    case unrestricted
}

public enum ContentWidth: String, CaseIterable {
    case medium
    case wide
    case unrestricted
}

public class PreferencesManager: ObservableObject {
    public static let shared = PreferencesManager()

    private let themeKey = "RedMargin.Preferences.Theme"
    private let showGutterKey = "RedMargin.Preferences.ShowGutter"
    private let showLineNumbersKey = "RedMargin.Preferences.ShowLineNumbers"
    private let showGitIndicatorsKey = "RedMargin.Preferences.ShowGitIndicators"
    private let allowRemoteImagesKey = "RedMargin.Preferences.AllowRemoteImages"
    private let inlineCodeColorKey = "RedMargin.Preferences.InlineCodeColor"
    private let textWidthKey = "RedMargin.Preferences.TextWidth"
    private let contentWidthKey = "RedMargin.Preferences.ContentWidth"
    private let printMarginKey = "RedMargin.Preferences.PrintMargin"
    private let showHiddenFilesKey = "RedMargin.Preferences.ShowHiddenFiles"

    @Published public var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: themeKey) }
    }

    @Published public var showGutter: Bool {
        didSet { UserDefaults.standard.set(showGutter, forKey: showGutterKey) }
    }

    @Published public var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: showLineNumbersKey) }
    }

    @Published public var showGitIndicators: Bool {
        didSet { UserDefaults.standard.set(showGitIndicators, forKey: showGitIndicatorsKey) }
    }

    @Published public var allowRemoteImages: Bool {
        didSet { UserDefaults.standard.set(allowRemoteImages, forKey: allowRemoteImagesKey) }
    }

    @Published public var inlineCodeColor: InlineCodeColor {
        didSet { UserDefaults.standard.set(inlineCodeColor.rawValue, forKey: inlineCodeColorKey) }
    }

    @Published public var textWidth: TextWidth {
        didSet { UserDefaults.standard.set(textWidth.rawValue, forKey: textWidthKey) }
    }

    @Published public var contentWidth: ContentWidth {
        didSet { UserDefaults.standard.set(contentWidth.rawValue, forKey: contentWidthKey) }
    }

    @Published public var printMargin: Double {
        didSet { UserDefaults.standard.set(printMargin, forKey: printMarginKey) }
    }

    @Published public var showHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: showHiddenFilesKey) }
    }

    private init() {
        let themeString = UserDefaults.standard.string(forKey: themeKey) ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeString) ?? .system

        self.showGutter = UserDefaults.standard.object(forKey: showGutterKey) as? Bool ?? true
        self.showLineNumbers = UserDefaults.standard.object(forKey: showLineNumbersKey) as? Bool ?? false
        self.showGitIndicators = UserDefaults.standard.object(forKey: showGitIndicatorsKey) as? Bool ?? true

        self.allowRemoteImages = UserDefaults.standard.object(forKey: allowRemoteImagesKey) as? Bool ?? false

        let colorString = UserDefaults.standard.string(forKey: inlineCodeColorKey) ?? InlineCodeColor.warm.rawValue
        self.inlineCodeColor = InlineCodeColor(rawValue: colorString) ?? .warm

        let textWidthString = UserDefaults.standard.string(forKey: textWidthKey) ?? TextWidth.medium.rawValue
        self.textWidth = TextWidth(rawValue: textWidthString) ?? .medium

        let contentWidthString = UserDefaults.standard.string(forKey: contentWidthKey)
            ?? ContentWidth.unrestricted.rawValue
        self.contentWidth = ContentWidth(rawValue: contentWidthString) ?? .unrestricted

        self.printMargin = UserDefaults.standard.object(forKey: printMarginKey) as? Double ?? 28

        self.showHiddenFiles = UserDefaults.standard.object(forKey: showHiddenFilesKey) as? Bool ?? false
    }
}
