import Foundation

class StorageUtils {

    enum Constants {
        static let firstEntranceKey = "PostedFirstEntranceFlag"
        static let deviceIDKey = "Posted_deviceId"
        static let attributionResolvedKey = "PostedAttributionResolved"
        static let cachedAttributionResultKey = "PostedCachedAttributionResult"

        // Legacy keys — used only during one-time migration
        static let legacyFirstEntranceKey = "DetourFirstEntranceFlag"
        static let legacyDeviceIDKey = "Detour_deviceId"
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

    // Stores result then sets the resolved flag — flag is never set without a decodable cached blob.
    static func markAttributionResolved(result: PostedResult) {
        let envelope = CachedAttribution(schemaVersion: CachedAttribution.currentVersion, result: result)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
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

    // One-time migration from legacy Detour keys → new Posted keys.
    // Safe to call multiple times; is a no-op once migration is complete.
    static func migrateKeysIfNeeded() {
        let defaults = UserDefaults.standard

        // Migrate firstEntrance flag — copy old value if new key not yet written
        if defaults.object(forKey: Constants.firstEntranceKey) == nil,
           defaults.bool(forKey: Constants.legacyFirstEntranceKey) {
            defaults.set(true, forKey: Constants.firstEntranceKey)
        }

        // Migrate deviceId — copy old value if new key not yet written
        if defaults.string(forKey: Constants.deviceIDKey) == nil,
           let legacyID = defaults.string(forKey: Constants.legacyDeviceIDKey),
           !legacyID.isEmpty {
            defaults.set(legacyID, forKey: Constants.deviceIDKey)
        }
    }
}
