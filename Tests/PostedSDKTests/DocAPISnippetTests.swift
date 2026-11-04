// Compile-checked mirror of the README snippets. Unlike the grep guard in
// scripts/static-check.sh, which only checks the symbols still exist, this file reproduces the
// exact call shapes the docs show, so a signature change fails compilation in the `test` CI job.
//
// Plain `import PostedSDK` (not @testable): these snippets must only use the genuinely public
// surface, matching what an integrator pastes from the README.
import PostedSDK
import XCTest

@MainActor
private enum DocAPISnippets {
    // README "2. Report the install"
    static func reportInstallSnippet() {
        let config = PostedConfig(
            apiKey: "<YOUR_API_KEY>",
            appID: "<YOUR_APP_ID>"
        )

        Task {
            await Posted.shared.reportInstall(config: config)
        }
    }
}

final class DocAPISnippetTests: XCTestCase {
    // Nothing to assert at runtime — DocAPISnippets only needs to type-check. This test exists
    // so the file is pulled into the compiled test target rather than discarded as dead code.
    func testDocSnippetsCompile() {
        XCTAssertTrue(true)
    }
}
