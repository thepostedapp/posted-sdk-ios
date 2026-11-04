import Foundation
import Combine

@MainActor
final class PostedDemoState: ObservableObject {
    static let shared = PostedDemoState()

    @Published var eventLog: [String] = []

    private init() {}

    func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        eventLog.insert("\(timestamp) \(message)", at: 0)

        if eventLog.count > 20 {
            eventLog = Array(eventLog.prefix(20))
        }
    }
}
