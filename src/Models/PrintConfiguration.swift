import Foundation

public struct PrintMargins: Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public init(
        top: Double = 56,
        right: Double = 28,
        bottom: Double = 56,
        left: Double = 28
    ) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static let `default` = PrintMargins()
}

public struct PrintConfiguration {
    public var includeGutter: Bool
    public var includeLineNumbers: Bool
    public var fontSize: Double
    public var margins: PrintMargins

    public init(
        includeGutter: Bool = true,
        includeLineNumbers: Bool = false,
        fontSize: Double = 15,
        margins: PrintMargins = .default
    ) {
        self.includeGutter = includeGutter
        self.includeLineNumbers = includeLineNumbers
        self.fontSize = fontSize
        self.margins = margins
    }

    public static let `default` = PrintConfiguration()
}
