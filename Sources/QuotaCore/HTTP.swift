import Foundation

/// The only way Quota talks to the network.
/// Ephemeral session (no cookies, no cache) and a hard allowlist of provider hosts.
public struct HTTPClient: Sendable {
    public static let allowedHosts: Set<String> = Set(ProviderID.allCases.flatMap(\.hosts))

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        guard url.scheme == "https", let host = url.host, Self.allowedHosts.contains(host) else {
            throw ProviderError.hostNotAllowed(url.host ?? "invalid URL")
        }
        // A pasted key with a line break would otherwise split the header.
        guard headers.values.allSatisfy({ !$0.contains(where: \.isNewline) }) else {
            throw ProviderError.unauthorized("Key contains a line break. Paste it again.")
        }
        var request = URLRequest(url: url)
        request.setValue("Quota/\(QuotaInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return data
        // Response bodies are never surfaced: they can echo request details.
        case 401, 403: throw ProviderError.unauthorized("Key rejected (HTTP \(status)).")
        default: throw ProviderError.http(status)
        }
    }
}

/// Redirects are never followed: they could carry the Authorization header, or the request itself,
/// to a host outside the allowlist. A 3xx response surfaces as an HTTP error instead.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

public enum QuotaInfo {
    public static let version = "0.1.0"
}
