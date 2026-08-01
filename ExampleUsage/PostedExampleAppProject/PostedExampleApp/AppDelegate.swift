import UIKit
import SwiftUI
import PostedSDK
import os

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let logger = Logger(subsystem: "<YOUR_BUNDLE_IDENTIFIER>", category: "AppDelegate")

    private let postedConfig = PostedConfig(
        apiKey: "<YOUR_POSTED_API_KEY>",
        appID: "<YOUR_POSTED_APP_ID>",
        shouldUseClipboard: false,
        linkProcessingMode: .all
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(
            rootView: ContentView()
        )
        window.makeKeyAndVisible()
        self.window = window

        // Mount analytics once at startup.
        Posted.shared.mountAnalytics(config: postedConfig)

        // Resolve the cold-start attribution branch (deferred or link-present) once.
        // Fire-once: subsequent calls within the same install return the cached result.
        Task { @MainActor in
            let result = await Posted.shared.resolveAppLaunch(
                config: postedConfig,
                launchContext: .launchOptions(launchOptions)
            )
            if let route = result.route {
                self.logger.info("Initial route: \(route)")
            } else {
                self.logger.info("No initial route")
            }

            PostedDemoState.shared.markInitialLinkResolved()
            PostedDemoState.shared.recordLinkResult(result, source: "cold_start")
        }

        return true
    }

    // Custom scheme, e.g. posted://product/42 (the `posted` scheme is registered in Info.plist)
    // Runtime links need no SDK call — parse the URL directly and navigate.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Task { @MainActor in
            PostedDemoState.shared.appendLog("[custom_scheme] url=\(url.absoluteString)")
        }

        return true
    }

    // Universal links, e.g. https://<YOUR_UNIVERSAL_LINK_DOMAIN>/promo/offer
    // Runtime links need no SDK call — parse the URL directly and navigate.
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }

        Task { @MainActor in
            PostedDemoState.shared.appendLog("[universal_link] url=\(url.absoluteString)")
        }

        return true
    }
}
