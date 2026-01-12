import Foundation

public struct PrintConfiguration {
    public var includeGutter: Bool
    public var includeLineNumbers: Bool

    public init(
        includeGutter: Bool = true,
        includeLineNumbers: Bool = false
    ) {
        self.includeGutter = includeGutter
        self.includeLineNumbers = includeLineNumbers
    }

    public static let `default` = PrintConfiguration()
}
