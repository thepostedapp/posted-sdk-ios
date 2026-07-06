// CONTRACT: The Flutter plugin ships a marker class at "PostedFlutterMarker" (new) or
// "DetourFlutterMarker" (legacy) with a static property exposed to ObjC as "sdkHeaderValue".
// Dual-lookup: try PostedFlutterMarker first, fall back to DetourFlutterMarker.
// If neither is found, reports as native iOS. Counterpart: detour-flutter-plugin/ios/Classes/DetourFlutterMarker.swift

import Foundation

enum PostedConstants {
    static let sdkType = "ios"
    static let flutterMarkerClassName = "PostedFlutterMarker"
    static let legacyFlutterMarkerClassName = "DetourFlutterMarker"
    static let flutterSdkHeaderSelector = NSSelectorFromString("sdkHeaderValue")
    // Keep the native SDK version explicit because static linking can place PostedSDK types
    // in the host app bundle, making bundle-based version lookup return the app version.
    static let sdkVersion = "3.0.0"
    static let sdkHeaderField = "X-SDK"
    static let sdkHeaderValue: String = {
        for className in [flutterMarkerClassName, legacyFlutterMarkerClassName] {
            if let markerClass = NSClassFromString(className) as? NSObject.Type,
               markerClass.responds(to: flutterSdkHeaderSelector),
               let value = markerClass.perform(flutterSdkHeaderSelector)?.takeUnretainedValue() as? String {
                // Flutter wrapper exposes the final header value directly to avoid static-lib bundle issues.
                return value
            }
        }

        // Fallback for pure native iOS SDK consumers.
        return "\(sdkType)/\(sdkVersion)"
    }()
    // TODO(B3): Backend API domain (godetour.dev) is intentionally kept until the
    // api.posted.app cutover is confirmed. The cutover is gated on D1 DNS (board-gated)
    // and must land in lockstep across all platform SDKs; do not change unilaterally.
    static let apiUrl: URL? = URL(string: "https://godetour.dev/api/link/match-link")
    static let resolveShortUrl: URL? = URL(string: "https://godetour.dev/api/link/resolve-short")
    static let analyticsEventUrl: URL? = URL(string: "https://godetour.dev/api/analytics/event")
    static let analyticsRetentionUrl: URL? = URL(string: "https://godetour.dev/api/analytics/retention")
    static let universalLinkClickUrl: URL? = URL(string: "https://godetour.dev/api/link/universal-link-click")
}
