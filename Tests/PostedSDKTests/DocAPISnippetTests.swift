// Compile-checked mirror of the README/CHANGELOG migration snippets for the 3 documented
// launch-API symbols (POS-171, follow-up to POS-168). Unlike the grep guard in
// scripts/static-check.sh — which only checks the symbols still exist — this file reproduces
// the exact call shapes the docs show. A signature change (e.g. a renamed parameter on
// resolveAppLaunch, a renamed LaunchContext case, or a resetSession param change) fails
// compilation here, in the `test` CI job, even if the symbol name itself is untouched.
//
// Plain `import PostedSDK` (not @testable): these snippets must only use the genuinely public
// surface, matching what an integrator pastes from the README.
import PostedSDK
import UIKit
import XCTest

@MainActor
private enum DocAPISnippets {
    // README "AppDelegate example"
    static func appDelegateSnippet(
        config: PostedConfig,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) async {
        let result = await Posted.shared.resolveAppLaunch(
            config: config,
            launchContext: .launchOptions(launchOptions)
        )
        _ = result.link
    }

    // README "SceneDelegate example"
    static func sceneDelegateSnippet(
        config: PostedConfig,
        connectionOptions: UIScene.ConnectionOptions
    ) async {
        let result = await Posted.shared.resolveAppLaunch(
            config: config,
            launchContext: .connectionOptions(connectionOptions)
        )
        _ = result.link
    }

    // README "Deferred-only (no URL context)" snippet
    static func deferredOnlySnippet(config: PostedConfig) async {
        _ = await Posted.shared.resolveAppLaunch(config: config)
    }

    // README "Call resetSession() to re-arm" snippet
    static func resetSessionSnippet() {
        Posted.shared.resetSession()
    }
}

final class DocAPISnippetTests: XCTestCase {
    // Nothing to assert at runtime — DocAPISnippets only needs to type-check. This test exists
    // so the file is pulled into the compiled test target rather than discarded as dead code.
    func testDocSnippetsCompile() {
        XCTAssertTrue(true)
    }
}
