// Tests for the connectionOptions -> LaunchContext.connectionOptions mapping (POS-173).
// UIScene.ConnectionOptions has no public initializer, so the mapping cannot be exercised by
// fabricating that argument directly. `_extractLaunchURL(fromConnectionOptions:)` in Posted.swift
// is the seam POS-173 introduces: it accepts anything conforming to `ConnectionOptionsMapping`,
// so the mapping can be asserted here with a fake conformance.
import XCTest
@testable import PostedSDK

private struct FakeConnectionOptionsMapping: ConnectionOptionsMapping {
    let mappedURLContextURL: URL?
    let mappedUserActivities: [NSUserActivity]
}

@MainActor
final class ConnectionOptionsMappingTests: XCTestCase {

    private func browsingActivity(webpageURL: URL?, activityType: String = NSUserActivityTypeBrowsingWeb) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.webpageURL = webpageURL
        return activity
    }

    func testURLContextURLIsReturnedDirectly() {
        let url = URL(string: "https://example.com/referral")!
        let mapping = FakeConnectionOptionsMapping(mappedURLContextURL: url, mappedUserActivities: [])

        let result = Posted.shared._extractLaunchURL(fromConnectionOptions: mapping)

        XCTAssertEqual(result, url)
    }

    func testInfrastructureURLContextURLIsIgnoredInFavorOfBrowsingActivity() {
        let webpageURL = URL(string: "https://example.com/handoff")!
        let mapping = FakeConnectionOptionsMapping(
            mappedURLContextURL: URL(string: "about:blank"),
            mappedUserActivities: [browsingActivity(webpageURL: webpageURL)]
        )

        let result = Posted.shared._extractLaunchURL(fromConnectionOptions: mapping)

        XCTAssertEqual(result, webpageURL)
    }

    func testNoURLContextFallsBackToBrowsingWebActivity() {
        let webpageURL = URL(string: "https://example.com/handoff")!
        let mapping = FakeConnectionOptionsMapping(
            mappedURLContextURL: nil,
            mappedUserActivities: [browsingActivity(webpageURL: webpageURL)]
        )

        let result = Posted.shared._extractLaunchURL(fromConnectionOptions: mapping)

        XCTAssertEqual(result, webpageURL)
    }

    func testNonBrowsingWebActivityIsIgnored() {
        let mapping = FakeConnectionOptionsMapping(
            mappedURLContextURL: nil,
            mappedUserActivities: [browsingActivity(webpageURL: URL(string: "https://example.com/other")!, activityType: "com.example.other")]
        )

        let result = Posted.shared._extractLaunchURL(fromConnectionOptions: mapping)

        XCTAssertNil(result)
    }

    func testNoURLContextAndNoActivitiesReturnsNil() {
        let mapping = FakeConnectionOptionsMapping(mappedURLContextURL: nil, mappedUserActivities: [])

        let result = Posted.shared._extractLaunchURL(fromConnectionOptions: mapping)

        XCTAssertNil(result)
    }
}
