import Foundation

enum PostedNetwork {
    private static let tag = "PostedApiClient"

    private static func applyHeaders(to request: inout URLRequest, config: PostedConfig) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(PostedConstants.sdkHeaderValue, forHTTPHeaderField: PostedConstants.sdkHeaderField)
    }

    // The backend's install schema is the install context fields plus `device_id`, in one flat
    // JSON object. iOS never sends `clickId`: the App Store passes no install referrer through.
    private static func installBody(installContext: InstallContext, deviceID: String) -> Data? {
        guard let data = try? JSONEncoder().encode(installContext),
              var body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        body["device_id"] = deviceID
        return try? JSONSerialization.data(withJSONObject: body)
    }

    /// POSTs the install report. Returns true only on a 2xx, so the caller arms its sent-once
    /// flag only when the backend accepted the install. Never throws.
    static func reportInstall(
        config: PostedConfig,
        installContext: InstallContext,
        deviceID: String,
        session: URLSession = .shared
    ) async -> Bool {
        guard let endpoint = PostedConstants.installUrl,
              let body = installBody(installContext: installContext, deviceID: deviceID) else {
            PostedLogger.error(tag, "[Posted:INSTALL_ERROR] Failed to build install report request")
            return false
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        applyHeaders(to: &request, config: config)
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                PostedLogger.warn(tag, "[Posted:INSTALL_ERROR] Failed to report install: \(status)")
                return false
            }
            PostedLogger.debug(tag, "Install reported")
            return true
        } catch {
            PostedLogger.error(tag, "[Posted:INSTALL_ERROR] Error reporting install:", error: error)
            return false
        }
    }
}
