import Foundation

typealias AnalyticsListener = (AnalyticsEventPayload) -> Void

@MainActor
final class AnalyticsEmitter {
    private static let tag = "PostedAnalytics"

    static let shared = AnalyticsEmitter()

    private var listeners: [UUID: AnalyticsListener] = [:]

    private init() {}

    func subscribe(_ listener: @escaping AnalyticsListener) -> UUID {
        let token = UUID()
        listeners[token] = listener
        return token
    }

    func unsubscribe(_ token: UUID) {
        listeners[token] = nil
    }

    func emit(_ payload: AnalyticsEventPayload) {
        let snapshot = Array(listeners.values)

        if snapshot.isEmpty {
            PostedLogger.warn(Self.tag, "[Posted:ANALYTICS] Analytics not initialized - call mount(config:) first")
            return
        }

        for listener in snapshot {
            listener(payload)
        }
    }
}
