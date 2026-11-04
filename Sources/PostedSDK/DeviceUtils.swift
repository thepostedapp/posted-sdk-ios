import Foundation
import UIKit
import WebKit

enum DeviceUtils {
    private static let tag = "InstallContextCollector"

    /// Each call owns its own WKWebView, retained only by the completion closure, so concurrent
    /// calls cannot tear down each other's in-flight evaluation. Internal (not private) so the
    /// concurrency test can drive two overlapping calls directly.
    @MainActor
    static func getRealUserAgent() async -> String {
        return await withCheckedContinuation { continuation in
            let webView = WKWebView()

            webView.evaluateJavaScript("navigator.userAgent") { result, error in
                if let error = error {
                    PostedLogger.warn(tag, "[Posted:INSTALL] WebKit userAgent retrieval failed: \(error.localizedDescription)")
                }

                if let ua = result as? String {
                    continuation.resume(returning: ua)
                } else {
                    PostedLogger.warn(tag, "[Posted:INSTALL] WebKit userAgent result was nil")
                    continuation.resume(returning: "")
                }

                _ = webView
            }
        }
    }

    // One user-agent lookup per process. An empty (failed) lookup is not kept, so a later
    // install report tries again.
    @MainActor private static var userAgentTask: Task<String, Never>?

    @MainActor
    static func sharedUserAgent() async -> String {
        if let userAgentTask { return await userAgentTask.value }
        let task = Task { await getRealUserAgent() }
        userAgentTask = task
        let userAgent = await task.value
        if userAgent.isEmpty, userAgentTask == task { userAgentTask = nil }
        return userAgent
    }

    // No clipboard read: it shows the iOS paste banner, and install matching doesn't use it.
    @MainActor
    static func collectInstallContext() async -> InstallContext {
        let device = UIDevice.current
        let screen = UIScreen.main
        let locales = Locale.preferredLanguages.map { LocaleTag(languageTag: $0) }
        let userAgent = await sharedUserAgent()

        return InstallContext(
            platform: "ios",
            model: device.model,
            manufacturer: "Apple",
            systemVersion: device.systemVersion,
            screenWidth: Double(screen.bounds.width),
            screenHeight: Double(screen.bounds.height),
            scale: Double(screen.scale),
            locale: locales,
            timezone: TimeZone.current.identifier,
            userAgent: userAgent,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}
