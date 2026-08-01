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
    // True when this result came from a genuine network/transport failure rather than a
    // legitimate "asked the server, no match" response. Deliberately kept out of `CodingKeys` so
    // the persisted fire-once cache envelope's JSON shape never changes — it must stay decodable
    // by installs that cached a result before this field existed. Only read this from a FRESH
    // completion result: a reloaded/cached result always decodes this as `false`, since fire-once
    // must never treat a persisted result as a failure.
    public let resolutionFailed: Bool

    public init(processed: Bool, link: PostedLink?) {
        self.processed = processed
        self.link = link
        self.resolutionFailed = false
    }

    init(processed: Bool, link: PostedLink?, resolutionFailed: Bool) {
        self.processed = processed
        self.link = link
        self.resolutionFailed = resolutionFailed
    }

    private enum CodingKeys: String, CodingKey {
        case processed, link
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processed = try container.decode(Bool.self, forKey: .processed)
        link = try container.decodeIfPresent(PostedLink.self, forKey: .link)
        resolutionFailed = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(processed, forKey: .processed)
        try container.encodeIfPresent(link, forKey: .link)
    }

    public var route: String? { link?.route }
    public var linkType: LinkType? { link?.type }
    public var pathname: String? { link?.pathname }
    public var params: [String: String] { link?.params ?? [:] }
    public var linkURL: URL? { link.flatMap { URL(string: $0.url) } }

    public static func empty() -> PostedResult {
        return PostedResult(processed: true, link: nil)
    }

    // Genuine resolution failure (transport error, non-2xx, decode/encode error, bad config URL) —
    // distinct from `.empty()`, which represents a successful call with no match. Fire-once must
    // not be set on this result so a later launch retries.
    static func failed() -> PostedResult {
        return PostedResult(processed: true, link: nil, resolutionFailed: true)
    }
}
