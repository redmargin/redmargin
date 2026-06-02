import Foundation

public enum AppVersion {
    private static let shortVersionKey = "CFBundleShortVersionString"
    private static let buildVersionKey = "CFBundleVersion"
    private static let unavailableVersion = "0.0.0"

    public static var current: String {
        value(from: Bundle.main.infoDictionary)
    }

    static func value(from infoDictionary: [String: Any]?) -> String {
        if let shortVersion = infoDictionary?[shortVersionKey] as? String, !shortVersion.isEmpty {
            return shortVersion
        }

        if let buildVersion = infoDictionary?[buildVersionKey] as? String, !buildVersion.isEmpty {
            return buildVersion
        }

        return unavailableVersion
    }
}
