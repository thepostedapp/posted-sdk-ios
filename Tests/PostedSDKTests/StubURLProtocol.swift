import Foundation

/// URLProtocol stub that intercepts all requests made through a custom URLSession.
/// Use `StubURLProtocol.makeSession()` to create a session backed by this stub,
/// then read `StubURLProtocol.capturedRequests` after the call to assert on the wire shape.
final class StubURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    static var responseStatusCode: Int = 200
    static var capturedRequests: [String: URLRequest] = [:]
    static var requestCallCount: [String: Int] = [:]

    static func reset() {
        responseData = Data()
        responseStatusCode = 200
        capturedRequests = [:]
        requestCallCount = [:]
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // URLSession moves httpBody into httpBodyStream when passing to URLProtocol.
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 4096)
                guard n > 0 else { break }
                data.append(buf, count: n)
            }
            stream.close()
            captured.httpBody = data
        }

        StubURLProtocol.capturedRequests[url.absoluteString] = captured
        StubURLProtocol.requestCallCount[url.absoluteString, default: 0] += 1

        let response = HTTPURLResponse(
            url: url,
            statusCode: StubURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
