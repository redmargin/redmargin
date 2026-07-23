import Foundation

extension Date {
    private static let relativeFullFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// Shared "2 days ago" phrasing for workspace rows and warnings.
    var relativeFullDescription: String {
        Self.relativeFullFormatter.localizedString(for: self, relativeTo: Date())
    }
}
