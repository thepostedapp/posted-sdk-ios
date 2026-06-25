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
        return try? JSONDecoder().decode(PostedResult.self, from: data)
    }

    static func markAttributionResolved(result: PostedResult) {
        UserDefaults.standard.set(true, forKey: Constants.attributionResolvedKey)
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Constants.cachedAttributionResultKey)
        }
    }

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
