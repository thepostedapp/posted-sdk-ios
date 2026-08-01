import Foundation
import UIKit

/// Represents the iOS-specific context that describes how the app was launched.
/// Pass the value received in `application(_:didFinishLaunchingWithOptions:)` or
/// `scene(_:willConnectTo:options:)` so the SDK can pick the correct attribution branch.
public enum LaunchContext: @unchecked Sendable {
    case launchOptions([UIApplication.LaunchOptionsKey: Any]?)
    case connectionOptions(UIScene.ConnectionOptions)
}

@MainActor
public class Posted {
    public static let shared = Posted()

    private let tag = "Posted"
    private var inFlightResolutionTask: Task<PostedResult, Never>?
    // Bumped by resetSession() so an in-flight resolution's completion can detect it was reset
    // mid-flight and skip re-marking fire-once — the reset must be honored, not clobbered.
    private var resolutionGeneration = 0

    private init() {
        StorageUtils.migrateKeysIfNeeded()
    }

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

    private func browsingWebActivities(from connectionOptions: UIScene.ConnectionOptions) -> [NSUserActivity] {
        connectionOptions.userActivities.filter { $0.activityType == NSUserActivityTypeBrowsingWeb }
    }

    // Converts a URL into a PostedResult with a parsed route.
    @available(*, deprecated, renamed: "resolveAppLaunch")
    public func processLink(_ url: URL) -> PostedResult {
        PostedLogger.warn(tag, "[Deprecated] processLink(_:) — migrate to resolveAppLaunch(config:launchContext:)")
        if LinkUtils.isInfrastructureUrl(url.absoluteString) {
            PostedLogger.debug(tag, "Ignored infrastructure URL: \(url.absoluteString)")
            return .empty()
        }

        let linkType = LinkUtils.detectLinkType(from: url)
        switch linkType {
        case .verified:
            PostedLogger.debug(tag, "Processing Universal Link")
        case .scheme:
            PostedLogger.debug(tag, "Processing Scheme Link")
        case .deferred:
            PostedLogger.debug(tag, "Processing Deferred Link")
        }
        let link = LinkUtils.makePostedLink(from: url, type: linkType)
        return PostedResult(processed: true, link: link)
    }

    // Processes URL and optionally resolves web short-links when config is provided.
    @available(*, deprecated, renamed: "resolveAppLaunch")
    public func processLink(_ url: URL, config: PostedConfig?) async -> PostedResult {
        PostedLogger.warn(tag, "[Deprecated] processLink(_:config:) — migrate to resolveAppLaunch(config:launchContext:)")
        if LinkUtils.detectLinkType(from: url) == .verified, let config {
            let clickResult = await PostedNetwork.sendUniversalLinkClick(config: config, url: url.absoluteString)
            if !clickResult.allowed {
                return .empty()
            }
        }
        return await processLink(url.absoluteString, config: config)
    }

    // Converts a raw link string into a PostedResult with route and link type.
    // If config is provided, web short-links are resolved before parsing.
    @available(*, deprecated, renamed: "resolveAppLaunch")
    public func processLink(_ rawLink: String, config: PostedConfig? = nil) async -> PostedResult {
        PostedLogger.warn(tag, "[Deprecated] processLink(_:config:) — migrate to resolveAppLaunch(config:launchContext:)")
        let resolvedLink = await resolveLink(rawLink, config: config)
        if resolvedLink == nil {
            PostedLogger.debug(tag, "No matching link found")
        }
        return PostedResult(processed: true, link: resolvedLink)
    }

    // Shared delegation core for both resolveInitialLink overloads. Internal so tests can
    // exercise the path directly when the overload's argument type is not unit-testable
    // (e.g. UIScene.ConnectionOptions has no public initializer).
    func _resolveInitialLink(
        config: PostedConfig,
        launchContext: LaunchContext?,
        completion: @escaping @Sendable (PostedResult) -> Void
    ) {
        Task {
            let result = await resolveAppLaunch(config: config, launchContext: launchContext)
            completion(result)
        }
    }

    @available(*, deprecated, renamed: "resolveAppLaunch")
    public func resolveInitialLink(
        config: PostedConfig,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        completion: @escaping @Sendable (PostedResult) -> Void
    ) {
        PostedLogger.warn(tag, "[Deprecated] resolveInitialLink — migrate to resolveAppLaunch(config:launchContext:)")
        _resolveInitialLink(config: config, launchContext: .launchOptions(launchOptions), completion: completion)
    }

    @available(*, deprecated, renamed: "resolveAppLaunch")
    public func resolveInitialLink(
        config: PostedConfig,
        connectionOptions: UIScene.ConnectionOptions,
        completion: @escaping @Sendable (PostedResult) -> Void
    ) {
        PostedLogger.warn(tag, "[Deprecated] resolveInitialLink — migrate to resolveAppLaunch(config:launchContext:)")
        _resolveInitialLink(config: config, launchContext: .connectionOptions(connectionOptions), completion: completion)
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

        if StorageUtils.isAttributionResolved(),
           let cached = StorageUtils.getCachedAttributionResult() {
            PostedLogger.debug(tag, "resolveAppLaunch: fire-once hit, returning cached result")
            return cached
        }

        // De-dup concurrent first-launch calls: if resolution is in-flight, await the same Task
        // so exactly one network call is made regardless of how many callers race on first launch.
        if let existing = inFlightResolutionTask {
            PostedLogger.debug(tag, "resolveAppLaunch: de-dup, awaiting in-flight resolution")
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
        defer { inFlightResolutionTask = nil }
        return await task.value
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
            if let url = connOptions.urlContexts.first?.url,
               !LinkUtils.isInfrastructureUrl(url.absoluteString) {
                return url
            }
            return browsingWebActivities(from: connOptions)
                .compactMap(\.webpageURL)
                .first { !LinkUtils.isInfrastructureUrl($0.absoluteString) }

        case .none:
            return nil
        }
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
