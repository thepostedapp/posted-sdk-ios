import Foundation

@MainActor
public final class PostedAnalytics {
    public static let shared = PostedAnalytics()

    private var isMounted = false
    private var subscriptionToken: UUID?
    private var hasLoggedColdStartRetention = false

    private init() {}

    public static func mount(config: PostedConfig) {
        shared.mount(config: config)
    }

    public static func unmount() {
        shared.unmount()
    }

    public static func logEvent(_ eventName: PostedEventName, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        shared.logEvent(eventName, data: data)
    }

    public static func logRetention(_ eventName: String) {
        shared.logRetention(eventName)
    }

    public func mount(config: PostedConfig) {
        guard !isMounted else { return }
        isMounted = true

        let token = AnalyticsEmitter.shared.subscribe { [weak self] payload in
            guard self != nil else { return }

            Task {
                let deviceID = DeviceIDPersistence.shared.prepareDeviceID()

                if payload.isRetention {
                    await AnalyticsNetwork.sendRetentionEvent(
                        config: config,
                        eventName: payload.eventName,
                        deviceID: deviceID
                    )
                } else {
                    await AnalyticsNetwork.sendEvent(
                        config: config,
                        eventName: payload.eventName,
                        data: payload.data,
                        deviceID: deviceID
                    )
                }
            }
        }

        subscriptionToken = token

        if !hasLoggedColdStartRetention {
            logRetention("app_open")
            hasLoggedColdStartRetention = true
        }
    }

    public func unmount() {
        guard isMounted else { return }
        isMounted = false

        guard let token = subscriptionToken else { return }
        subscriptionToken = nil
        AnalyticsEmitter.shared.unsubscribe(token)
    }

    public func logEvent(_ eventName: PostedEventName, data: [String: Any]? = nil) {
        logEvent(eventName.rawValue, data: data)
    }

    public func logEvent(_ eventName: String, data: [String: Any]? = nil) {
        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: data, isRetention: false)
        )
    }

    public func logRetention(_ eventName: String) {
        AnalyticsEmitter.shared.emit(
            AnalyticsEventPayload(eventName: eventName, data: nil, isRetention: true)
        )
    }
}
