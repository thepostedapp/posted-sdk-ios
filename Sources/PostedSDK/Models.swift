import Foundation

public struct PostedConfig: Sendable {
    public let apiKey: String
    public let appID: String
    public let shouldUseClipboard: Bool
    public let linkProcessingMode: LinkProcessingMode

    public init(
        apiKey: String,
        appID: String,
        shouldUseClipboard: Bool = true,
        linkProcessingMode: LinkProcessingMode = .all
    ) {
        self.apiKey = apiKey
        self.appID = appID
        self.shouldUseClipboard = shouldUseClipboard
        self.linkProcessingMode = linkProcessingMode
    }
}

public enum LinkProcessingMode: String, Sendable {
    case all
    case webOnly = "web-only"
    case deferredOnly = "deferred-only"
}

public enum LinkType: String, Codable, Sendable {
    case deferred
    case verified
    case scheme
}

public struct PostedLink: Sendable, Codable {
    public let url: String
    public let route: String
    public let pathname: String
    public let params: [String: String]
    public let type: LinkType

    public init(
        url: String,
        route: String,
        pathname: String,
        params: [String: String],
        type: LinkType
    ) {
        self.url = url
        self.route = route
        self.pathname = pathname
        self.params = params
        self.type = type
    }
}

struct ProbabilisticFingerprint: Codable {
    let platform: String
    let model: String
    let manufacturer: String
    let systemVersion: String
    let screenWidth: Double
    let screenHeight: Double
    let scale: Double
    let locale: [LocaleTag]
    let timezone: String
    let userAgent: String
    let timestamp: Int64
    let pastedLink: String?
}

struct LocaleTag: Codable {
    let languageTag: String
}

public struct PostedResult: Sendable, Codable {
    public let processed: Bool
    public let link: PostedLink?

    public init(processed: Bool, link: PostedLink?) {
        self.processed = processed
        self.link = link
    }

    public var route: String? { link?.route }
    public var linkType: LinkType? { link?.type }
    public var pathname: String? { link?.pathname }
    public var params: [String: String] { link?.params ?? [:] }
    public var linkURL: URL? { link.flatMap { URL(string: $0.url) } }

    public static func empty() -> PostedResult {
        return PostedResult(processed: true, link: nil)
    }
}
