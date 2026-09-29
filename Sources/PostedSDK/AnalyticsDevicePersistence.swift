import Foundation

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
        UserDefaults.standard.synchronize()
        cachedDeviceID = newID
        return newID
    }
}
