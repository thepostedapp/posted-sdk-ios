import Foundation

/// URLProtocol stub that intercepts all requests made through a custom URLSession.
/// Use `StubURLProtocol.makeSession()` to create a session backed by this stub,
/// then read `StubURLProtocol.capturedRequests` after the call to assert on the wire shape.
final class StubURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    static var responseStatusCode: Int = 200
    static var capturedRequests: [String: URLRequest] = [:]
    static var requestCallCount: [String: Int] = [:]

    // Gated handshake: when set, startLoading() signals `requestReceived` as soon as it has
    // captured the request, then blocks on `releaseResponse` before sending the response. This
    // lets a test deterministically force overlap between an in-flight network call and other
    // work without relying on sleeps/timing. Both run on URLSession's own
    // loading-queue thread, never the main/actor thread, so blocking here cannot deadlock callers.
    static var requestReceived: DispatchSemaphore?
    static var releaseResponse: DispatchSemaphore?
    // When set, only requests to this URL go through the gate above; every other request is
    // answered at once. Lets a test hold one endpoint while the rest of the flow completes.
    static var gatedURL: String?

    static func reset() {
        responseData = Data()
        responseStatusCode = 200
        capturedRequests = [:]
        requestCallCount = [:]
        requestReceived = nil
        releaseResponse = nil
        gatedURL = nil
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

        // Snapshot the gate + response config before signaling. A test that reassigns
        // requestReceived/releaseResponse/responseData to gate a second overlapping call while
        // this request is still parked between signal() and wait() would otherwise race: this
        // request could pick up the OTHER call's semaphore (deadlock — nothing left waiting on
        // its own releaseResponse) or its response payload. Pinning everything to the values in
        // effect when this load started makes the load immune to later reassignment.
        let isGated = StubURLProtocol.gatedURL.map { $0 == url.absoluteString } ?? true
        let requestReceivedSemaphore = isGated ? StubURLProtocol.requestReceived : nil
        let releaseResponseSemaphore = isGated ? StubURLProtocol.releaseResponse : nil
        let responseData = StubURLProtocol.responseData
        let responseStatusCode = StubURLProtocol.responseStatusCode

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

        requestReceivedSemaphore?.signal()
        releaseResponseSemaphore?.wait()

        let response = HTTPURLResponse(
            url: url,
            statusCode: responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
