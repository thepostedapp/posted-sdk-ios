import Foundation

enum AnalyticsNetwork {
    private static let tag = "AnalyticsApiClient"

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeTimestamp() -> String {
        return timestampFormatter.string(from: Date())
    }

    private static func baseRequest(
        url: URL?,
        config: PostedConfig
    ) -> URLRequest? {
        guard let url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(PostedConstants.sdkHeaderValue, forHTTPHeaderField: PostedConstants.sdkHeaderField)
        return request
    }

    private static func commonBody(eventName: String, deviceID: String) -> [String: Any] {
        return [
            "event_name": eventName,
            "timestamp": makeTimestamp(),
            "platform": "ios",
            "device_id": deviceID,
        ]
    }

    private static func send(
        config: PostedConfig,
        url: URL?,
        eventName: String,
        deviceID: String,
        data: [String: Any]?,
        kind: String,
        session: URLSession = .shared
    ) async {
        guard var request = baseRequest(url: url, config: config) else { return }

        var body = commonBody(eventName: eventName, deviceID: deviceID)
        if let data, JSONSerialization.isValidJSONObject(data) {
            body["data"] = data
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            PostedLogger.warn(tag, "[Posted:ANALYTICS] Failed to encode \(kind) body.")
            return
        }

        request.httpBody = bodyData

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            if !(200 ... 299).contains(httpResponse.statusCode) {
                PostedLogger.warn(tag, "[Posted:ANALYTICS] \(kind) send failed: \(httpResponse.statusCode)")
            }
        } catch {
            PostedLogger.warn(tag, "[Posted:ANALYTICS] \(kind) send exception: \(error.localizedDescription)")
        }
    }

    static func sendEvent(config: PostedConfig, eventName: String, data: [String: Any]?, deviceID: String, session: URLSession = .shared) async {
        await send(
            config: config,
            url: PostedConstants.analyticsEventUrl,
            eventName: eventName,
            deviceID: deviceID,
            data: data,
            kind: "event",
            session: session
        )
    }

    static func sendRetentionEvent(config: PostedConfig, eventName: String, deviceID: String, session: URLSession = .shared) async {
        await send(
            config: config,
            url: PostedConstants.analyticsRetentionUrl,
            eventName: eventName,
            deviceID: deviceID,
            data: nil,
            kind: "retention event",
            session: session
        )
    }
}
