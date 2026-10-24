import Foundation

class StorageUtils {

    private static let tag = "StorageUtils"

    enum Constants {
        static let firstEntranceKey = "PostedFirstEntranceFlag"
        static let deviceIDKey = "Posted_deviceId"
        static let attributionResolvedKey = "PostedAttributionResolved"
        static let cachedAttributionResultKey = "PostedCachedAttributionResult"
        // Same key as the RN SDK. Deliberately NOT cleared by resetSession(): an install is
        // reported once per device.
        static let installReportedKey = "Posted_installReported"
    }

    // Versioned envelope for the cached PostedResult.
    // On schema version mismatch getCachedAttributionResult returns nil (drop + re-resolve).
    private struct CachedAttribution: Codable {
        static let currentVersion = 1
        let schemaVersion: Int
        let result: PostedResult
    }

    static func isFirstEntrance() -> Bool {
        return !UserDefaults.standard.bool(forKey: Constants.firstEntranceKey)
    }

    static func markFirstEntrance() {
        UserDefaults.standard.set(true, forKey: Constants.firstEntranceKey)
    }

    static func resetFirstEntrance() {
        UserDefaults.standard.set(false, forKey: Constants.firstEntranceKey)
    }

    // MARK: - Install report

    static func isInstallReported() -> Bool {
        return UserDefaults.standard.bool(forKey: Constants.installReportedKey)
    }

    static func markInstallReported() {
        UserDefaults.standard.set(true, forKey: Constants.installReportedKey)
    }

    static func clearInstallReported() {
        UserDefaults.standard.removeObject(forKey: Constants.installReportedKey)
    }

    // MARK: - Fire-once attribution persistence

    static func isAttributionResolved() -> Bool {
        return UserDefaults.standard.bool(forKey: Constants.attributionResolvedKey)
    }

    static func getCachedAttributionResult() -> PostedResult? {
        guard let data = UserDefaults.standard.data(forKey: Constants.cachedAttributionResultKey) else { return nil }
        guard let envelope = try? JSONDecoder().decode(CachedAttribution.self, from: data),
              envelope.schemaVersion == CachedAttribution.currentVersion else {
            return nil
        }
        return envelope.result
    }

#if DEBUG
    // Test-only hook — false in production. PostedResult/PostedLink have no Double/Float fields,
    // so there is no way to produce a genuinely un-encodable envelope through the public API;
    // this hook forces markAttributionResolved(result:) down its encode-failure branch so that
    // branch (and the STORAGE_WRITE_FAILED log it emits) can be covered by a test.
    static var _forceEncodeFailureForTesting = false
    private static var isEncodeFailureForced: Bool { _forceEncodeFailureForTesting }
#else
    private static var isEncodeFailureForced: Bool { false }
#endif

    // Stores result then sets the resolved flag — flag is never set without a decodable cached blob.
    static func markAttributionResolved(result: PostedResult) {
        let envelope = CachedAttribution(schemaVersion: CachedAttribution.currentVersion, result: result)
        guard !isEncodeFailureForced, let data = try? JSONEncoder().encode(envelope) else {
            PostedLogger.debug(tag, "[Posted:STORAGE_WRITE_FAILED] Failed to encode fire-once result; flag not armed, next launch will re-resolve.")
            return
        }
        UserDefaults.standard.set(data, forKey: Constants.cachedAttributionResultKey)
        UserDefaults.standard.set(true, forKey: Constants.attributionResolvedKey)
    }

    // Ordering is the safety mechanism, not an implementation detail: the flag MUST be removed
    // BEFORE the blob. UserDefaults has no multi-remove/batch API (unlike Android's
    // SharedPreferences.Editor, see POS-346), so a crash/kill between these two calls can tear
    // this clear. Flag-first means the only observable torn state is "flag gone, blob present,"
    // which the read path (isAttributionResolved() && getCachedAttributionResult() must both
    // hold, see Posted.swift's resolveAppLaunch) already treats as unresolved and safely
    // re-resolves. Reordering to blob-first would reintroduce a hazard: "flag present, blob
    // gone" reads as resolved with a nil cache, which callers do not defend against.
    static func clearAttributionResolved() {
        UserDefaults.standard.removeObject(forKey: Constants.attributionResolvedKey)
        UserDefaults.standard.removeObject(forKey: Constants.cachedAttributionResultKey)
    }
}
