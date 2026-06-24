import Foundation

class StorageUtils {

    enum Constants {
        static let firstEntranceKey = "PostedFirstEntranceFlag"
        static let deviceIDKey = "Posted_deviceId"

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
