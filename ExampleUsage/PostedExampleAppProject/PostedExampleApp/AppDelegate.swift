import UIKit
import SwiftUI
import PostedSDK

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let postedConfig = PostedConfig(
        apiKey: "<YOUR_POSTED_API_KEY>",
        appID: "<YOUR_POSTED_APP_ID>"
    )

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: ContentView())
        window.makeKeyAndVisible()
        self.window = window

        // Report the install on every launch. The SDK sends it once per install and retries on
        // later launches until the backend accepts it. No need to wait for it.
        Task { @MainActor in
            PostedDemoState.shared.appendLog("reportInstall called")
            await Posted.shared.reportInstall(config: postedConfig)
            PostedDemoState.shared.appendLog("reportInstall finished (see Console for the result)")
        }

        return true
    }
}
