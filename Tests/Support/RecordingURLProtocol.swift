import Foundation
@testable import PersonalStylist

/// Records every request that enters URL loading and returns scripted results (#220).
///
/// **Scope note:** `URLProtocol` only sees requests after `URLSession` starts loading.
/// Use `OutfitEngineClient.requestLifecycleObserver` to assert "constructed but not
/// dispatched" (e.g. cancel before `resume`) vs "never constructed" (auth fail-closed).
final class RecordingURLProtocol: URLProtocol {
    struct RecordedRequest: Equatable {
        var method: String
        var path: String
        var body: Data?
        var url: URL
    }

    enum StubResult {
        case http(status: Int, headers: [String: String] = ["Content-Type": "application/json"], body: Data)
        case transportError(Error)
        /// Completes only after `finishHang` — use for cancellation / latency demos.
        case hang
    }

    private static let lock = NSLock()
    private static var _recorded: [RecordedRequest] = []
    private static var _handler: ((URLRequest) -> StubResult)?
    private static var _latencyNanoseconds: UInt64 = 0
    private static var _enabled = false
    private static var hangContinuations: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]

    static var recorded: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    static var latencyNanoseconds: UInt64 {
        get { lock.lock(); defer { lock.unlock() }; return _latencyNanoseconds }
        set { lock.lock(); _latencyNanoseconds = newValue; lock.unlock() }
    }

    static func install(handler: @escaping (URLRequest) -> StubResult) {
        lock.lock()
        _handler = handler
        _recorded = []
        _enabled = true
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _recorded = []
        _latencyNanoseconds = 0
        _enabled = false
        hangContinuations.removeAll()
        lock.unlock()
    }

    static func finishHang() {
        lock.lock()
        let pending = hangContinuations
        hangContinuations.removeAll()
        lock.unlock()
        for (_, cont) in pending {
            cont.resume()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _enabled
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let url = request.url ?? URL(string: "about:blank")!
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: url.path,
            body: request.httpBody ?? Self.bodyFromStream(request),
            url: url
        )

        Self.lock.lock()
        Self._recorded.append(recorded)
        let handler = Self._handler
        let delay = Self._latencyNanoseconds
        Self.lock.unlock()

        let result = handler?(request) ?? .http(
            status: 500,
            body: Data(#"{"title":"unstubbed","status":500}"#.utf8)
        )

        Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            await self.deliver(result)
        }
    }

    override func stopLoading() {
        // Cancellation is observed via the URLSession completion / URLError.cancelled.
    }

    private func deliver(_ result: StubResult) async {
        switch result {
        case let .http(status, headers, body):
            let url = request.url ?? URL(string: "about:blank")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .transportError(error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hang:
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                Self.lock.lock()
                Self.hangContinuations[ObjectIdentifier(self)] = cont
                Self.lock.unlock()
            }
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        }
    }

    private static func bodyFromStream(_ request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}

enum EngineURLSessionStub {
    /// Ephemeral session whose loading stack is only `RecordingURLProtocol`.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }

    /// Loopback HTTP base so generate/alternatives skip device-token auth.
    static let stubBaseURL = URL(string: "http://127.0.0.1:8787")!

    static func installClientHooks(
        handler: @escaping (URLRequest) -> RecordingURLProtocol.StubResult
    ) {
        RecordingURLProtocol.install(handler: handler)
        OutfitEngineClient.urlSession = makeSession()
        OutfitEngineClient.baseURLOverride = stubBaseURL
    }

    static func tearDownClientHooks() {
        RecordingURLProtocol.reset()
        OutfitEngineClient.resetTestHooks()
    }
}
