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

    private init() {
        let themeString = UserDefaults.standard.string(forKey: themeKey) ?? Theme.system.rawValue
        self.theme = Theme(rawValue: themeString) ?? .system

        let gutterString = UserDefaults.standard.string(forKey: gutterVisibilityKey) ?? GutterVisibility.showEmpty.rawValue
        self.gutterVisibilityForNonRepo = GutterVisibility(rawValue: gutterString) ?? .showEmpty

        self.allowRemoteImages = UserDefaults.standard.object(forKey: allowRemoteImagesKey) as? Bool ?? false

        let colorString = UserDefaults.standard.string(forKey: inlineCodeColorKey) ?? InlineCodeColor.warm.rawValue
        self.inlineCodeColor = InlineCodeColor(rawValue: colorString) ?? .warm
    }
}
