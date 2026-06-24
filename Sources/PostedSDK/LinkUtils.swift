import Foundation

class LinkUtils {
    static func getRestOfPath(_ pathname: String) -> String {
        // Safety check: needs at least 2 chars (e.g. "/a") to possibly have a second slash
        if pathname.count < 2 { return "/" }

        let searchStartIndex = pathname.index(pathname.startIndex, offsetBy: 1)

        // Find the index of the second slash
        if let secondSlashIndex = pathname[searchStartIndex...].firstIndex(of: "/") {
            // Return everything from that slash onwards
            return String(pathname[secondSlashIndex...])
        }

        // If no second slash found return root
        return "/"
    }

    static func isInfrastructureUrl(_ rawUrl: String) -> Bool {
        if rawUrl.isEmpty {
            return true
        }

        if rawUrl == "about:blank" { return true }

        return false
    }

    private static func routeFromWebUrl(_ url: URL) -> String {
        let fullPath = url.path
        var finalRoute = getRestOfPath(fullPath)

        if let query = url.query {
            finalRoute += "?\(query)"
        }

        return finalRoute
    }

    static func routeFromDeepLink(_ url: URL) -> String {
        let host = url.host ?? ""
        let route = host + url.path + (url.query.map { "?\($0)" } ?? "")
        return route.hasPrefix("/") ? route : "/\(route)"
    }

    static func extractRoute(from url: URL) -> String {
        return isWebUrl(url.absoluteString, parsedUrl: url) ? routeFromWebUrl(url) : routeFromDeepLink(url)
    }

    static func normalizeRawLink(_ rawLink: String) -> String {
        if rawLink.hasPrefix("//") {
            return "https:\(rawLink)"
        }
        return rawLink
    }

    static func looksLikeUrl(_ rawLink: String) -> Bool {
        return rawLink.contains("://") || rawLink.hasPrefix("//")
    }

    static func detectLinkType(from url: URL, override: LinkType? = nil) -> LinkType {
        if let override {
            return override
        }

        return isWebUrl(url.absoluteString, parsedUrl: url) ? .verified : .scheme
    }

    static func extractRoute(from rawLink: String) -> String {
        if !looksLikeUrl(rawLink) {
            return rawLink.hasPrefix("/") ? rawLink : "/\(rawLink)"
        }

        let normalized = normalizeRawLink(rawLink)
        guard let parsedUrl = URL(string: normalized) else {
            return rawLink
        }

        return extractRoute(from: parsedUrl)
    }

    static func isWebUrl(_ rawLink: String, parsedUrl: URL? = nil) -> Bool {
        if rawLink.hasPrefix("//") { return true }
        if let parsedUrl {
            let scheme = parsedUrl.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
        return rawLink.lowercased().hasPrefix("http://") || rawLink.lowercased().hasPrefix("https://")
    }

    static func parseParams(from query: String?) -> [String: String] {
        guard let query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = components.first else { continue }
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let rawValue = components.count > 1 ? String(components[1]) : ""
            let value = rawValue.removingPercentEncoding ?? rawValue
            result[key] = value
        }
        return result
    }

    static func makePostedLink(from url: URL, type: LinkType) -> PostedLink {
        let route = extractRoute(from: url)
        let pathname = route.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? route
        return PostedLink(
            url: url.absoluteString,
            route: route,
            pathname: pathname.isEmpty ? "/" : pathname,
            params: parseParams(from: url.query),
            type: type
        )
    }

    static func makePostedLink(fromPath rawPath: String, type: LinkType) -> PostedLink {
        let normalized = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        let parts = normalized.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let fullPathname = parts.first ?? "/"
        let query = parts.count > 1 ? parts[1] : nil

        let pathname = getRestOfPath(fullPathname)
        let route = pathname + (query.map { "?\($0)" } ?? "")

        return PostedLink(
            url: normalized,
            route: route,
            pathname: pathname,
            params: parseParams(from: query),
            type: type
        )
    }
}
