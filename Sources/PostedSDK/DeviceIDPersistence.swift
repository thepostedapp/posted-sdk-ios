import Foundation

// A random, per-install device id. Generated once and persisted; reinstalling clears it.
@MainActor
final class DeviceIDPersistence {
    static let shared = DeviceIDPersistence()

    private var cachedDeviceID: String?

    private init() {}

    func prepareDeviceID() -> String {
        if let cachedDeviceID {
            return cachedDeviceID
        }

        if let existingID = UserDefaults.standard.string(forKey: StorageUtils.Constants.deviceIDKey),
           !existingID.isEmpty {
            cachedDeviceID = existingID
            return existingID
        }

        let newID = UUID().uuidString.lowercased()
        UserDefaults.standard.set(newID, forKey: StorageUtils.Constants.deviceIDKey)
        cachedDeviceID = newID
        return newID
    }
}
