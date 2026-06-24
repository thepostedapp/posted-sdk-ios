import UIKit
import WebKit

class DeviceUtils {
    private static let tag = "FingerprintCollector"

    @MainActor
    private static var webView: WKWebView?

    @MainActor
    private static func getRealUserAgent() async -> String {
        return await withCheckedContinuation { continuation in
            webView = WKWebView()

            webView?.evaluateJavaScript("navigator.userAgent") { result, error in
                if let error = error {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent retrieval failed: \(error.localizedDescription)")
                }

                if let ua = result as? String {
                    continuation.resume(returning: ua)
                } else {
                    PostedLogger.warn(tag, "[Posted:FINGERPRINT] WebKit userAgent result was nil")
                    continuation.resume(returning: "")
                }

                webView = nil
            }
        }
    }

    @MainActor
    private static func readClipboardLinkIfAvailable(shouldUseClipboard: Bool) async -> String? {
        guard shouldUseClipboard else { return nil }

        if #available(iOS 14.0, *) {
            let hasProbableWebURL = await withCheckedContinuation { continuation in
                UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                    switch result {
                    case .success(let patterns):
                        continuation.resume(returning: patterns.contains(.probableWebURL))
                    case .failure:
                        continuation.resume(returning: false)
                    }
                }
            }

            guard hasProbableWebURL else { return nil }
        }

        return UIPasteboard.general.string
    }

    @MainActor
    static func getFingerprint(shouldUseClipboard: Bool) async -> ProbabilisticFingerprint {
        let device = UIDevice.current
        let screen = UIScreen.main

        let pastedLink = await readClipboardLinkIfAvailable(shouldUseClipboard: shouldUseClipboard)

        let locales = Locale.preferredLanguages.map { LocaleTag(languageTag: $0) }

        let userAgent = await getRealUserAgent()

        return ProbabilisticFingerprint(
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
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            pastedLink: pastedLink
        )
    }
}
