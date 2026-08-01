import Foundation
import Combine
import PostedSDK

@MainActor
final class PostedDemoState: ObservableObject {
    static let shared = PostedDemoState()

    @Published var isResolvingInitialLink: Bool = true
    @Published var lastRoute: String = "No route yet"
    @Published var lastLinkType: String = "-"
    @Published var eventLog: [String] = []

    private init() {}

    func recordLinkResult(_ result: PostedResult, source: String) {
        if let route = result.route {
            lastRoute = route
        }

        if let linkType = result.linkType {
            lastLinkType = linkType.rawValue
        }

        let linkValue = result.link?.url ?? "nil"
        appendLog("[\(source)] route=\(result.route ?? "nil"), linkType=\(result.linkType?.rawValue ?? "nil"), link=\(linkValue)")
    }

    func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        eventLog.insert("\(timestamp) \(message)", at: 0)

        if eventLog.count > 20 {
            eventLog = Array(eventLog.prefix(20))
        }
    }

    func markInitialLinkResolved() {
        isResolvingInitialLink = false
    }
}
