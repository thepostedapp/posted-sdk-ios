import Foundation

class DetourNetwork {
    private static let tag = "DetourApiClient"

    private struct LinkResponse: Decodable {
        let link: String?
    }

    private static func applyHeaders(to request: inout URLRequest, config: DetourConfig) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(DetourConstants.sdkHeaderValue, forHTTPHeaderField: DetourConstants.sdkHeaderField)
    }

    private static func logAndFail(
        _ message: String,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        DetourLogger.error(tag, "[Detour:NETWORK_ERROR] \(message)")

        DispatchQueue.main.async {
            completion(.empty())
        }
    }

    static func matchLink(
        config: DetourConfig,
        fingerprint: ProbabilisticFingerprint,
        linkType: LinkType = .deferred,
        session: URLSession = .shared,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {

        guard let apiUrl = DetourConstants.apiUrl else {
            logAndFail("Configuration Error: Invalid API URL", completion: completion)
            return
        }

        let httpBody: Data
        do {
            httpBody = try JSONEncoder().encode(fingerprint)
        } catch {
            logAndFail("Encoding Error: Failed to encode fingerprint - \(error.localizedDescription)", completion: completion)
            return
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config)
        request.httpBody = httpBody

        DetourLogger.debug(tag, "Sending fingerprint to API")

        session.dataTask(with: request) { data, response, error in
            handleResponse(
                data: data,
                response: response,
                error: error,
                linkType: linkType,
                completion: completion
            )
        }.resume()
    }

    private static func handleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        linkType: LinkType,
        completion: @escaping @Sendable (DetourResult) -> Void
    ) {
        if let transportError = error {
            logAndFail("Network Error: \(transportError.localizedDescription)", completion: completion)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            DispatchQueue.main.async { completion(.empty()) }
            return
        }

        if !(200 ... 299).contains(httpResponse.statusCode) {
            var errorMessage = "Request failed"

            if let errorData = data,
               let json = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
               let errorContent = json["error"]
            {
                if let strError = errorContent as? String {
                    errorMessage = strError
                } else if let errorBytes = try? JSONSerialization.data(withJSONObject: errorContent),
                          let strified = String(data: errorBytes, encoding: .utf8)
                {
                    errorMessage = strified
                }
            }

            logAndFail("Server Error: \(errorMessage)", completion: completion)
            return
        }

        guard let responseData = data else {
            logAndFail("Parsing Error: Response data was nil", completion: completion)
            return
        }

        do {
            let response = try JSONDecoder().decode(LinkResponse.self, from: responseData)

            if let linkString = response.link,
               let url = URL(string: linkString) {
                DetourLogger.debug(tag, "Link matched successfully")
                let detourLink = LinkUtils.makeDetourLink(from: url, type: linkType)
                DispatchQueue.main.async {
                    completion(DetourResult(processed: true, link: detourLink))
                }
            } else {
                DetourLogger.debug(tag, "No matching link found")
                DispatchQueue.main.async { completion(.empty()) }
            }
        } catch {
            logAndFail("JSON Parsing Error: \(error.localizedDescription)", completion: completion)
        }
    }

    static func resolveShortLink(config: DetourConfig, url: String, session: URLSession = .shared) async -> URL? {
        guard let endpoint = DetourConstants.resolveShortUrl else {
            DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution failed: invalid endpoint")
            return nil
        }

        let normalizedInput = LinkUtils.normalizeRawLink(url)

        guard let requestBody = try? JSONEncoder().encode(["url": url]) else {
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        applyHeaders(to: &request, config: config)
        request.httpBody = requestBody

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            if httpResponse.statusCode == 404 { return nil }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution failed: \(httpResponse.statusCode)")
                return nil
            }

            let decodedResponse = try JSONDecoder().decode(LinkResponse.self, from: data)
            guard let linkString = decodedResponse.link,
                  let resolvedURL = URL(string: linkString) else {
                return nil
            }

            let normalizedResolved = LinkUtils.normalizeRawLink(resolvedURL.absoluteString)
            if normalizedResolved == normalizedInput {
                return nil
            }

            DetourLogger.debug(tag, "Short link resolved successfully")
            return resolvedURL
        } catch {
            DetourLogger.warn(tag, "[Detour:NETWORK_ERROR] Short link resolution exception: \(error.localizedDescription)")
            return nil
        }
    }

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }

    static func sendUniversalLinkClick(config: DetourConfig, url: String, linkId: String? = nil, session: URLSession = .shared) async -> (allowed: Bool, clickId: String?) {
        guard let endpoint = DetourConstants.universalLinkClickUrl else {
            return (allowed: true, clickId: nil)  // fail-open
        }

        struct Metadata: Encodable {
            let os_version: String
            let app_version: String
            let device_model: String
        }

        struct RequestBody: Encodable {
            let link_id: String?
            let url: String
            let timestamp: Int64
            let platform: String
            let params: [String: String]?
            let metadata: Metadata

            enum CodingKeys: String, CodingKey {
                case link_id, url, timestamp, platform, params, metadata
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let id = link_id { try container.encode(id, forKey: .link_id) }
                try container.encode(url, forKey: .url)
                try container.encode(timestamp, forKey: .timestamp)
                try container.encode(platform, forKey: .platform)
                if let params = params, !params.isEmpty { try container.encode(params, forKey: .params) }
                try container.encode(metadata, forKey: .metadata)
            }
        }

        struct ResponseBody: Decodable {
            let allowed: Bool?
            let clickId: String?
            let error: String?
            let code: String?
            let clicksInPeriod: Int?
            let effectiveLimit: Int?
            let remainingClicks: Int?
        }

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let urlParams = URLComponents(string: url)?.queryItems?.reduce(into: [String: String]()) {
            $0[$1.name] = $1.value ?? ""
        }

        let requestBody = RequestBody(
            link_id: linkId,
            url: url,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            platform: "ios",
            params: urlParams,
            metadata: Metadata(
                os_version: osVersionString,
                app_version: appVersion,
                device_model: deviceModel()
            )
        )

        guard let body = try? JSONEncoder().encode(requestBody) else {
            return (allowed: true, clickId: nil)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        applyHeaders(to: &request, config: config)
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (allowed: true, clickId: nil) }

            let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)
            let isExplicitDeny = decoded?.allowed == false || http.statusCode == 402

            if isExplicitDeny {
                DetourLogger.error(
                    tag,
                    "[Detour:CLICK_LIMIT_ERROR] Universal link blocked: url=\(url) error=\(decoded?.error ?? "limit exceeded") code=\(decoded?.code ?? "n/a") clicksInPeriod=\(decoded?.clicksInPeriod.map(String.init) ?? "n/a") effectiveLimit=\(decoded?.effectiveLimit.map(String.init) ?? "n/a")"
                )
                return (allowed: false, clickId: nil)
            }

            if !(200...299).contains(http.statusCode) {
                return (allowed: true, clickId: nil)  // fail-open on backend errors
            }

            return (allowed: true, clickId: decoded?.clickId)
        } catch {
            return (allowed: true, clickId: nil)  // fail-open on network errors
        }
    }
}
