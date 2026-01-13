import WebKit

/// Generates WKContentRuleList configurations for security
public enum ContentRuleList {

    /// Rule that blocks all remote URL loads (http/https)
    public static let blockAllRemote = """
    [
        {
            "trigger": {
                "url-filter": "^https?://",
                "resource-type": ["image", "style-sheet", "script", "font", "media", "raw", "document", "popup"]
            },
            "action": {
                "type": "block"
            }
        }
    ]
    """

    /// Rule that allows remote images but blocks other remote resources
    public static let allowRemoteImages = """
    [
        {
            "trigger": {
                "url-filter": "^https?://",
                "resource-type": ["style-sheet", "script", "font", "media", "raw", "document", "popup"]
            },
            "action": {
                "type": "block"
            }
        }
    ]
    """

    /// Compiles a rule list asynchronously
    public static func compile(
        _ rules: String,
        identifier: String,
        completion: @escaping (WKContentRuleList?) -> Void
    ) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: rules
        ) { ruleList, error in
            if let error = error {
                print("Failed to compile content rules '\(identifier)': \(error)")
            }
            completion(ruleList)
        }
    }

    /// Compiles and returns the appropriate rule list based on preference
    public static func compileForPreference(
        allowRemoteImages: Bool,
        completion: @escaping (WKContentRuleList?) -> Void
    ) {
        let rules = allowRemoteImages ? Self.allowRemoteImages : Self.blockAllRemote
        let identifier = allowRemoteImages ? "allowRemoteImages" : "blockAllRemote"
        compile(rules, identifier: identifier, completion: completion)
    }
}
