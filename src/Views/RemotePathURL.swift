import Foundation

public extension URL {
    static func redmarginRemotePath(_ path: String) -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "redmargin-remote:\(encoded)") ?? URL(string: "redmargin-remote:/")!
    }
}
