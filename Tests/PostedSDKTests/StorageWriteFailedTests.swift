// Coverage for POS-500: markAttributionResolved(result:)'s encode-failure branch must log
// STORAGE_WRITE_FAILED and leave the fire-once flag unset. PostedResult/PostedLink have no
// Double/Float fields, so JSONEncoder cannot genuinely fail on them through the public API —
// StorageUtils._forceEncodeFailureForTesting (DEBUG-only) drives the branch instead.
import XCTest
@testable import PostedSDK

@MainActor
final class StorageWriteFailedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.attributionResolvedKey)
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.cachedAttributionResultKey)
    }

    override func tearDown() {
        StorageUtils._forceEncodeFailureForTesting = false
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.attributionResolvedKey)
        UserDefaults.standard.removeObject(forKey: StorageUtils.Constants.cachedAttributionResultKey)
        super.tearDown()
    }

    func testEncodeFailureLogsStorageWriteFailedAndLeavesFlagUnset() {
        var capturedDebugMessages: [(String, String)] = []
        PostedLogger._debugSink = { tag, message in capturedDebugMessages.append((tag, message)) }
        defer { PostedLogger._debugSink = nil }

        StorageUtils._forceEncodeFailureForTesting = true
        StorageUtils.markAttributionResolved(result: PostedResult(processed: true, link: nil))

        XCTAssertFalse(
            StorageUtils.isAttributionResolved(),
            "encode failure must not arm the fire-once flag — next launch should re-resolve"
        )
        XCTAssertNil(
            StorageUtils.getCachedAttributionResult(),
            "encode failure must not write a cached blob"
        )
        XCTAssertTrue(
            capturedDebugMessages.contains { $0.1.contains("[Posted:STORAGE_WRITE_FAILED]") },
            "encode failure must emit a debug log tagged STORAGE_WRITE_FAILED"
        )
    }

    func testSuccessPathIsUnaffectedAndLogsNothing() {
        var capturedDebugMessages: [(String, String)] = []
        PostedLogger._debugSink = { tag, message in capturedDebugMessages.append((tag, message)) }
        defer { PostedLogger._debugSink = nil }

        StorageUtils.markAttributionResolved(result: PostedResult(processed: true, link: nil))

        XCTAssertTrue(StorageUtils.isAttributionResolved())
        XCTAssertNotNil(StorageUtils.getCachedAttributionResult())
        XCTAssertFalse(
            capturedDebugMessages.contains { $0.1.contains("[Posted:STORAGE_WRITE_FAILED]") },
            "the success path must not emit the STORAGE_WRITE_FAILED marker"
        )
    }
}
