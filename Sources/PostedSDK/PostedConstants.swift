// CONTRACT: The Flutter plugin ships a marker class at "PostedFlutterMarker" with a static
// property exposed to ObjC as "sdkHeaderValue". If not found, reports as native iOS.
// Counterpart: posted-sdk-flutter/ios/Classes/PostedFlutterMarker.swift

import Foundation

enum PostedConstants {
    static let sdkType = "ios"
    static let flutterMarkerClassName = "PostedFlutterMarker"
    static let flutterSdkHeaderSelector = NSSelectorFromString("sdkHeaderValue")
    // Keep the native SDK version explicit because static linking can place PostedSDK types
    // in the host app bundle, making bundle-based version lookup return the app version.
    static let sdkVersion = "1.0.1"
    static let sdkHeaderField = "X-SDK"
    static let sdkHeaderValue: String = {
        if let markerClass = NSClassFromString(flutterMarkerClassName) as? NSObject.Type,
           markerClass.responds(to: flutterSdkHeaderSelector),
           let value = markerClass.perform(flutterSdkHeaderSelector)?.takeUnretainedValue() as? String {
            // Flutter wrapper exposes the final header value directly to avoid static-lib bundle issues.
            return value
        }

        // Fallback for pure native iOS SDK consumers.
        return "\(sdkType)/\(sdkVersion)"
    }()
    static let installUrl: URL? = URL(string: "https://attr.postedapp.com/api/install")
}
