import Foundation

enum StorageUtils {
    // Key names are persisted on existing installs and shared with the other platform SDKs.
    // Never rename them.
    enum Constants {
        static let deviceIDKey = "Posted_deviceId"
        static let installReportedKey = "Posted_installReported"
        static let revenueCatUserReportedKey = "Posted_revenueCatUserReported"
    }

    static func isInstallReported() -> Bool {
        return UserDefaults.standard.bool(forKey: Constants.installReportedKey)
    }

    static func markInstallReported() {
        UserDefaults.standard.set(true, forKey: Constants.installReportedKey)
    }

    static func clearInstallReported() {
        UserDefaults.standard.removeObject(forKey: Constants.installReportedKey)
    }

    static func isRevenueCatUserReported() -> Bool {
        return UserDefaults.standard.bool(forKey: Constants.revenueCatUserReportedKey)
    }

    static func markRevenueCatUserReported() {
        UserDefaults.standard.set(true, forKey: Constants.revenueCatUserReportedKey)
    }

    static func clearRevenueCatUserReported() {
        UserDefaults.standard.removeObject(forKey: Constants.revenueCatUserReportedKey)
    }
}
