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

        // Resolve initial deferred/universal link.
        Posted.shared.resolveInitialLink(config: postedConfig, launchOptions: launchOptions) { result in
            if let route = result.route {
                self.logger.info("Initial route: \(route)")
            } else {
                self.logger.info("No initial route")
            }

            Task { @MainActor in
                DetourDemoState.shared.markInitialLinkResolved()
                DetourDemoState.shared.recordLinkResult(result, source: "cold_start")
            }
        }

        return true
    }

    // Custom scheme, e.g. <YOUR_CUSTOM_SCHEME>://product/42
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Task { @MainActor in
            let result = await Posted.shared.processLink(url, config: postedConfig)
            DetourDemoState.shared.recordLinkResult(result, source: "custom_scheme")
        }

        return true
    }

    // Universal links, e.g. https://<YOUR_UNIVERSAL_LINK_DOMAIN>/promo/offer
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
            let result = await Posted.shared.processLink(url, config: postedConfig)
            DetourDemoState.shared.recordLinkResult(result, source: "universal_link")
        }

        return true
    }
}
