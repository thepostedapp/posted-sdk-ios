import Foundation

/// Reports app installs to Posted, so the backend can match each install to the ad click that
/// led to it and report it back to the ad network as a conversion.
///
/// The SDK has one entry point, `reportInstall(config:)`. Call it on every app launch; it sends
/// the report once per install.
@MainActor
public class Posted {
    public static let shared = Posted()

    private let tag = "Posted"
    // Single-flight: concurrent callers on first launch share one request.
    private var inFlightInstallReport: Task<Void, Never>?
    private var inFlightPurchasesUserReport: Task<Void, Never>?

    private init() {}

    // The Task itself (not a Bool) so tests can await a report started by a concurrent caller.
    var debugInFlightInstallReport: Task<Void, Never>? { inFlightInstallReport }

    /// Reports this install for ad attribution.
    ///
    /// Safe to call on every launch: the install is sent once, and retried on later launches
    /// until the backend accepts it. Never throws and never reads the clipboard. You don't need
    /// to wait for it; wrap the call in a `Task` and let it run in the background.
    public func reportInstall(config: PostedConfig) async {
        await _reportInstall(config: config, session: .shared)
    }

    func _reportInstall(config: PostedConfig, session: URLSession) async {
        if let existing = inFlightInstallReport {
            await existing.value
            return
        }
        guard !StorageUtils.isInstallReported() else { return }

        let task = Task<Void, Never> { [weak self] in
            let installContext = await DeviceUtils.collectInstallContext()
            let deviceID = DeviceIDPersistence.shared.prepareDeviceID()
            if await PostedNetwork.reportInstall(
                config: config,
                installContext: installContext,
                deviceID: deviceID,
                session: session
            ) {
                StorageUtils.markInstallReported()
            }
            self?.inFlightInstallReport = nil
        }
        inFlightInstallReport = task
        await task.value
    }

    /// Links the RevenueCat or Superwall user id to this install, so purchases can be attributed.
    ///
    /// Call it after the purchases SDK is configured. The id is sent once per install, and retried on
    /// later calls until the backend accepts it. Never throws.
    public func setPurchasesUserId(_ id: String, config: PostedConfig) async {
        await _setPurchasesUserId(id, config: config, session: .shared)
    }

    func _setPurchasesUserId(_ id: String, config: PostedConfig, session: URLSession) async {
        if let existing = inFlightPurchasesUserReport {
            await existing.value
            return
        }
        guard !id.isEmpty, !StorageUtils.isPurchasesUserReported() else { return }

        let task = Task<Void, Never> { [weak self] in
            // The backend links the id to an existing install, so the install goes first.
            await self?._reportInstall(config: config, session: session)
            if StorageUtils.isInstallReported(),
               await PostedNetwork.reportPurchasesUser(
                   config: config,
                   deviceID: DeviceIDPersistence.shared.prepareDeviceID(),
                   purchasesUserID: id,
                   session: session
               ) {
                StorageUtils.markPurchasesUserReported()
            }
            self?.inFlightPurchasesUserReport = nil
        }
        inFlightPurchasesUserReport = task
        await task.value
    }
}
