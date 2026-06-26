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

    private var isSessionHandled = false
    private var inFlightResolutionTask: Task<PostedResult, Never>?
    private let tag = "Posted"

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
        isSessionHandled = false
        inFlightResolutionTask = nil
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

    private func resolveDeferredInitialLink(
        config: PostedConfig,
        completion: @escaping @Sendable (PostedResult) -> Void
    ) {
        if !StorageUtils.isFirstEntrance() {
            PostedLogger.debug(tag, "Not first launch")
            isSessionHandled = true
            completion(.empty())
            return
        }

        StorageUtils.markFirstEntrance()
        isSessionHandled = true
        PostedLogger.debug(tag, "First launch detected, processing deferred link")
        PostedLogger.debug(tag, "Using probabilistic matching")

        Task {
            let fingerprint = await DeviceUtils.getFingerprint(shouldUseClipboard: config.shouldUseClipboard)
            PostedNetwork.matchLink(config: config, fingerprint: fingerprint, linkType: .deferred) { result in
                Task { @MainActor [weak self] in
                    guard let self else {
                        completion(result)
                        return
                    }

                    let filteredResult = self.filterNonWebUrlLikeLinks(result, mode: config.linkProcessingMode)
                    if filteredResult.link == nil {
                        PostedLogger.debug(self.tag, "No deferred link matched")
                    } else {
                        PostedLogger.debug(self.tag, "Deferred link matched successfully")
                    }
                    completion(filteredResult)
                }
            }
        }
    }

    // Converts a URL into a PostedResult with a parsed route.
    public func processLink(_ url: URL) -> PostedResult {
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
    public func processLink(_ url: URL, config: PostedConfig?) async -> PostedResult {
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
    public func processLink(_ rawLink: String, config: PostedConfig? = nil) async -> PostedResult {
        let resolvedLink = await resolveLink(rawLink, config: config)
        if resolvedLink == nil {
            PostedLogger.debug(tag, "No matching link found")
        }
        return PostedResult(processed: true, link: resolvedLink)
    }

    public func resolveInitialLink(
            config: PostedConfig,
            launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
            completion: @escaping @Sendable (PostedResult) -> Void
        ) {
            mountAnalytics(config: config)

            func returnEmpty() { completion(.empty()) }

            if isSessionHandled {
                PostedLogger.debug(tag, "Session already handled")
                returnEmpty()
                return
            }

            if config.linkProcessingMode != .deferredOnly {
                if let launchURL = launchOptions?[.url] as? URL,
                   !LinkUtils.isInfrastructureUrl(launchURL.absoluteString)
                {
                    PostedLogger.debug(tag, "Processing launch URL")
                    StorageUtils.markFirstEntrance()
                    isSessionHandled = true
                    Task {
                        let result = await processLink(launchURL.absoluteString, config: config)
                        completion(result)
                    }
                    return
                }

                let activities = browsingWebActivities(from: launchOptions)
                if let universalURL = activities.compactMap(\.webpageURL).first,
                   !LinkUtils.isInfrastructureUrl(universalURL.absoluteString)
                {
                    PostedLogger.debug(tag, "Processing Universal Link")
                    StorageUtils.markFirstEntrance()
                    isSessionHandled = true
                    Task {
                        let result = await processLink(universalURL, config: config)
                        completion(result)
                    }
                    return
                }

                if !activities.isEmpty {
                    PostedLogger.debug(tag, "Universal Link userActivity detected - awaiting continueUserActivity callback")
                    StorageUtils.markFirstEntrance()
                    isSessionHandled = true
                    // UIApplicationDelegate will invoke continueUserActivity next.
                    returnEmpty()
                    return
                }
            }

            PostedLogger.debug(tag, "Falling back to deferred link resolution")
            resolveDeferredInitialLink(config: config, completion: completion)
        }

    public func resolveInitialLink(
        config: PostedConfig,
        connectionOptions: UIScene.ConnectionOptions,
        completion: @escaping @Sendable (PostedResult) -> Void
    ) {
        mountAnalytics(config: config)

        func returnEmpty() { completion(.empty()) }

        if isSessionHandled {
            PostedLogger.debug(tag, "Session already handled")
            returnEmpty()
            return
        }

        if config.linkProcessingMode != .deferredOnly {
            if let openURL = connectionOptions.urlContexts.first?.url,
               !LinkUtils.isInfrastructureUrl(openURL.absoluteString)
            {
                PostedLogger.debug(tag, "Processing launch URL")
                StorageUtils.markFirstEntrance()
                isSessionHandled = true
                Task {
                    let result = await processLink(openURL.absoluteString, config: config)
                    completion(result)
                }
                return
            }

            let activities = browsingWebActivities(from: connectionOptions)
            if let universalURL = activities.compactMap(\.webpageURL).first,
               !LinkUtils.isInfrastructureUrl(universalURL.absoluteString)
            {
                PostedLogger.debug(tag, "Processing Universal Link")
                StorageUtils.markFirstEntrance()
                isSessionHandled = true
                Task {
                    let result = await processLink(universalURL, config: config)
                    completion(result)
                }
                return
            }

            if !activities.isEmpty {
                PostedLogger.debug(tag, "Universal Link userActivity detected - awaiting continue callback")
                StorageUtils.markFirstEntrance()
                isSessionHandled = true
                returnEmpty()
                return
            }
        }

        PostedLogger.debug(tag, "Falling back to deferred link resolution")
        resolveDeferredInitialLink(config: config, completion: completion)
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
            StorageUtils.markAttributionResolved(result: result)
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
