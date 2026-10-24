import Foundation
import UIKit

/// Represents the iOS-specific context that describes how the app was launched.
/// Pass the value received in `application(_:didFinishLaunchingWithOptions:)` or
/// `scene(_:willConnectTo:options:)` so the SDK can pick the correct attribution branch.
public enum LaunchContext: @unchecked Sendable {
    case launchOptions([UIApplication.LaunchOptionsKey: Any]?)
    case connectionOptions(UIScene.ConnectionOptions)
}

// Abstracts the subset of UIScene.ConnectionOptions that resolveAppLaunch's
// .connectionOptions(_:) branch maps into a launch URL. UIScene.ConnectionOptions has no public
// initializer, so this seam is what lets that mapping be exercised with a fake conformance in
// unit tests (POS-173).
protocol ConnectionOptionsMapping {
    var mappedURLContextURL: URL? { get }
    var mappedUserActivities: [NSUserActivity] { get }
}

extension UIScene.ConnectionOptions: ConnectionOptionsMapping {
    var mappedURLContextURL: URL? { urlContexts.first?.url }
    var mappedUserActivities: [NSUserActivity] { Array(userActivities) }
}

@MainActor
public class Posted {
    public static let shared = Posted()

    private let tag = "Posted"
    private var inFlightResolutionTask: Task<PostedResult, Never>?
    // Bumped by resetSession() so an in-flight resolution's completion can detect it was reset
    // mid-flight and skip re-marking fire-once, and skip clearing `inFlightResolutionTask` if a
    // fresher post-reset resolution has since taken it over — the reset must be honored, not
    // clobbered, and a de-duped caller must not trigger a duplicate network call.
    private var resolutionGeneration = 0
    // Single-flight for the install report: resolveAppLaunch and a manual reportInstall call
    // may race on first launch; both share this one request.
    private var inFlightInstallReport: Task<Void, Never>?

    private init() {}

    // Internal-only bookkeeping accessors (POS-267). `@testable import` exposes `internal` members
    // to the test target, letting tests assert the epoch guard directly right after resetSession()
    // instead of needing a second live network race to prove a de-duped caller would no longer see
    // the stale in-flight task.
    var debugResolutionGeneration: Int { resolutionGeneration }
    var debugHasInFlightResolutionTask: Bool { inFlightResolutionTask != nil }
    // The Task itself (not a Bool like the accessor above) so tests can await the
    // fire-and-forget install report that resolveAppLaunch starts.
    var debugInFlightInstallReport: Task<Void, Never>? { inFlightInstallReport }

    public func mountAnalytics(config: PostedConfig) {
        PostedAnalytics.mount(config: config)
    }

    public func unmountAnalytics() {
        PostedAnalytics.unmount()
    }

    public func resetSession(allowDeferredRetry: Bool = false) {
        inFlightResolutionTask = nil
        resolutionGeneration += 1
        StorageUtils.clearAttributionResolved()
        PostedLogger.debug(tag, "Session reset")
        if allowDeferredRetry {
            StorageUtils.resetFirstEntrance()
            PostedLogger.debug(tag, "Deferred retry enabled - first entrance flag reset")
        }
    }

    private func filterNonWebUrlLikeLinks(_ result: PostedResult, mode: LinkProcessingMode) -> PostedResult {
        guard mode != .all else { return result }
        guard let link = result.link else { return result }

        let parsed = URL(string: link.url)
        let isWeb = LinkUtils.isWebUrl(link.url, parsedUrl: parsed)

        if LinkUtils.looksLikeUrl(link.url), !isWeb {
            PostedLogger.debug(tag, "Non-web URL-like link filtered by mode \(mode.rawValue)")
            return .empty()
        }

        return result
    }

    private func resolveLink(
        _ rawLink: String,
        config: PostedConfig?,
        typeOverride: LinkType? = nil,
        visitedShortLinks: Set<String> = [],
        session: URLSession = .shared
    ) async -> PostedLink? {
        if LinkUtils.isInfrastructureUrl(rawLink) {
            PostedLogger.debug(tag, "Ignored infrastructure URL: \(rawLink)")
            return nil
        }

        let mode = config?.linkProcessingMode ?? .all

        if !LinkUtils.looksLikeUrl(rawLink) {
            return LinkUtils.makePostedLink(fromPath: rawLink, type: typeOverride ?? .verified)
        }

        let normalized = LinkUtils.normalizeRawLink(rawLink)
        guard let url = URL(string: normalized) else {
            let isWeb = LinkUtils.isWebUrl(rawLink)
            if !isWeb && mode != .all {
                PostedLogger.debug(tag, "Custom scheme link ignored in mode \(mode.rawValue)")
                return nil
            }

            PostedLogger.warn(tag, "[Posted:TYPE_ERROR] Failed to parse URL, falling back to raw string")
            let fallbackType = typeOverride ?? (isWeb ? .verified : .scheme)
            return PostedLink(
                url: rawLink,
                route: rawLink,
                pathname: rawLink,
                params: [:],
                type: fallbackType
            )
        }

        let isWeb = LinkUtils.isWebUrl(rawLink, parsedUrl: url)
        if !isWeb && mode != .all {
            PostedLogger.debug(tag, "Custom scheme link ignored in mode \(mode.rawValue)")
            return nil
        }

        let type = typeOverride ?? (isWeb ? .verified : .scheme)

        if isWeb {
            let pathSegments = url.path.split(separator: "/").map(String.init)
            let isSingleSegmentPath = pathSegments.count == 1 && !pathSegments[0].isEmpty

            if isSingleSegmentPath, let config {
                var visited = visitedShortLinks
                visited.insert(normalized)

                if let resolvedUrl = await PostedNetwork.resolveShortLink(config: config, url: rawLink, session: session) {
                    let normalizedResolved = LinkUtils.normalizeRawLink(resolvedUrl.absoluteString)
                    if !visited.contains(normalizedResolved) {
                        return await resolveLink(
                            normalizedResolved,
                            config: config,
                            visitedShortLinks: visited,
                            session: session
                        )
                    }
                }
            }
        }

        return LinkUtils.makePostedLink(from: url, type: type)
    }

    private func browsingWebActivities(
        from launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> [NSUserActivity] {
        guard let activityDict = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] else {
            return []
        }

        return activityDict.values.compactMap { value in
            guard let activity = value as? NSUserActivity else { return nil }
            return activity.activityType == NSUserActivityTypeBrowsingWeb ? activity : nil
        }
    }

    private func browsingWebActivities(from connectionOptions: ConnectionOptionsMapping) -> [NSUserActivity] {
        connectionOptions.mappedUserActivities.filter { $0.activityType == NSUserActivityTypeBrowsingWeb }
    }

    // MARK: - resolveAppLaunch (3.0.0 facade)

    /// Resolves attribution exactly once per install, returning a cached result on subsequent calls.
    ///
    /// Pass the `launchContext` from your app/scene delegate so the SDK can choose the correct
    /// internal branch: link-present (universal / scheme URL) or deferred (probabilistic match).
    /// Omit `launchContext` when the launch carries no URL (deferred-only scenarios).
    public func resolveAppLaunch(
        config: PostedConfig,
        launchContext: LaunchContext? = nil
    ) async -> PostedResult {
        await _resolveAppLaunch(config: config, launchContext: launchContext, session: .shared)
    }

    func _resolveAppLaunch(
        config: PostedConfig,
        launchContext: LaunchContext? = nil,
        session: URLSession
    ) async -> PostedResult {
        mountAnalytics(config: config)

        // The install report is started on every call, including the fire-once and de-dup
        // returns: a launch whose attribution is already cached must still retry an install
        // report that failed earlier. It is fire-and-forget and never changes the result.
        if StorageUtils.isAttributionResolved(),
           let cached = StorageUtils.getCachedAttributionResult() {
            PostedLogger.debug(tag, "resolveAppLaunch: fire-once hit, returning cached result")
            startInstallReport(config: config, session: session)
            return cached
        }

        // De-dup concurrent first-launch calls: if resolution is in-flight, await the same Task
        // so exactly one network call is made regardless of how many callers race on first launch.
        if let existing = inFlightResolutionTask {
            PostedLogger.debug(tag, "resolveAppLaunch: de-dup, awaiting in-flight resolution")
            startInstallReport(config: config, session: session)
            return await existing.value
        }

        let launchURL = extractLaunchURL(from: launchContext, config: config)
        let generation = resolutionGeneration

        let task = Task<PostedResult, Never> { [weak self] in
            guard let self else { return .empty() }
            let result: PostedResult
            if let url = launchURL {
                PostedLogger.debug(self.tag, "resolveAppLaunch: link-present branch")
                result = await self.resolveLinkPresent(url: url, config: config, session: session)
            } else {
                PostedLogger.debug(self.tag, "resolveAppLaunch: deferred branch")
                result = await self.resolveAppLaunchDeferred(config: config, session: session)
            }
            if self.resolutionGeneration != generation {
                PostedLogger.debug(self.tag, "resolveAppLaunch: resetSession invoked mid-resolve, discarding stale fire-once write")
            } else if result.resolutionFailed {
                PostedLogger.debug(self.tag, "resolveAppLaunch: resolution failed, fire-once not set — a later launch will retry")
            } else {
                StorageUtils.markAttributionResolved(result: result)
            }
            return result
        }
        inFlightResolutionTask = task
        // Started after the resolution task so link resolution runs first on the main actor; the
        // install report then reuses the fingerprint's shared user agent instead of its own WKWebView.
        startInstallReport(config: config, session: session)
        defer {
            // Only clear the in-flight pointer if no resetSession() happened since this call
            // started. Otherwise a stale resolution settling after a reset would clobber the
            // bookkeeping for a fresher in-flight resolution started post-reset, causing a
            // duplicate network call for a de-duped caller (the double-fire companion of the
            // fire-once-clobber race above).
            if resolutionGeneration == generation {
                inFlightResolutionTask = nil
            }
        }
        return await task.value
    }

    // MARK: - Install report

    /// Reports this install for ad attribution, so the backend can match it to the ad click that
    /// led here and report it as a conversion.
    ///
    /// `resolveAppLaunch(config:launchContext:)` already does this automatically. Call this
    /// directly only if your app resolves deep links without `resolveAppLaunch`. Safe to call on
    /// every launch: the install is sent once, and retried on later launches until the backend
    /// accepts it. Never throws. Only `apiKey` and `appID` are used from `config`; the clipboard
    /// is never read.
    public func reportInstall(config: PostedConfig) async {
        await _reportInstall(config: config, session: .shared)
    }

    func _reportInstall(config: PostedConfig, session: URLSession) async {
        await startInstallReport(config: config, session: session)?.value
    }

    @discardableResult
    private func startInstallReport(config: PostedConfig, session: URLSession) -> Task<Void, Never>? {
        if let existing = inFlightInstallReport { return existing }
        guard !StorageUtils.isInstallReported() else { return nil }

        let task = Task<Void, Never> { [weak self] in
            // No clipboard: reading it shows the iOS paste banner, and install matching doesn't use it.
            let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: false)
            let deviceID = DeviceIDPersistence.shared.prepareDeviceID()
            if await PostedNetwork.reportInstall(
                config: config,
                fingerprint: fingerprint,
                deviceID: deviceID,
                session: session
            ) {
                StorageUtils.markInstallReported()
            }
            self?.inFlightInstallReport = nil
        }
        inFlightInstallReport = task
        return task
    }

    private func extractLaunchURL(from launchContext: LaunchContext?, config: PostedConfig) -> URL? {
        guard config.linkProcessingMode != .deferredOnly else { return nil }

        switch launchContext {
        case .launchOptions(let options):
            if let url = options?[.url] as? URL,
               !LinkUtils.isInfrastructureUrl(url.absoluteString) {
                return url
            }
            return browsingWebActivities(from: options)
                .compactMap(\.webpageURL)
                .first { !LinkUtils.isInfrastructureUrl($0.absoluteString) }

        case .connectionOptions(let connOptions):
            return _extractLaunchURL(fromConnectionOptions: connOptions)

        case .none:
            return nil
        }
    }

    // Internal so tests can exercise the connectionOptions -> launch URL mapping in isolation
    // with a fake ConnectionOptionsMapping conformance (POS-173) — UIScene.ConnectionOptions
    // itself has no public initializer and cannot be fabricated in a unit test.
    func _extractLaunchURL(fromConnectionOptions connOptions: ConnectionOptionsMapping) -> URL? {
        if let url = connOptions.mappedURLContextURL,
           !LinkUtils.isInfrastructureUrl(url.absoluteString) {
            return url
        }
        return browsingWebActivities(from: connOptions)
            .compactMap(\.webpageURL)
            .first { !LinkUtils.isInfrastructureUrl($0.absoluteString) }
    }

    private func resolveLinkPresent(url: URL, config: PostedConfig, session: URLSession) async -> PostedResult {
        if LinkUtils.detectLinkType(from: url) == .verified {
            let clickResult = await PostedNetwork.sendUniversalLinkClick(
                config: config,
                url: url.absoluteString,
                session: session
            )
            if !clickResult.allowed { return .empty() }
        }
        let resolved = await resolveLink(url.absoluteString, config: config, session: session)
        return PostedResult(processed: true, link: resolved)
    }

    private func resolveAppLaunchDeferred(config: PostedConfig, session: URLSession) async -> PostedResult {
        PostedLogger.debug(tag, "Using probabilistic matching")
        let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
        return await withCheckedContinuation { continuation in
            PostedNetwork.matchLink(
                config: config,
                fingerprint: fingerprint,
                linkType: .deferred,
                session: session
            ) { result in
                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: result)
                        return
                    }
                    let filtered = self.filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
                    if filtered.link == nil {
                        PostedLogger.debug(self.tag, "resolveAppLaunch: no deferred link matched")
                    } else {
                        PostedLogger.debug(self.tag, "resolveAppLaunch: deferred link matched")
                    }
                    continuation.resume(returning: filtered)
                }
            }
        }
    }

}
