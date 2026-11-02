import Foundation

/// Credentials for your app, from the Posted dashboard.
public struct PostedConfig: Sendable {
    /// Your API key from the dashboard.
    public let apiKey: String
    /// Your app ID from the dashboard.
    public let appID: String

    public init(apiKey: String, appID: String) {
        self.apiKey = apiKey
        self.appID = appID
    }
}

// The device signals the backend matches an install to the ad click that led to it. Field
// names are the wire format shared with the other platform SDKs: never rename them.
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
}

struct LocaleTag: Codable {
    let languageTag: String
}
