import Foundation
import Testing
@testable import QuotaCore

@Suite struct SecurityTests {
    @Test func refusesHostsOffTheAllowlist() async {
        let http = HTTPClient()
        await #expect(throws: ProviderError.hostNotAllowed("example.com")) {
            try await http.get(URL(string: "https://example.com/")!, headers: [:])
        }
        await #expect(throws: ProviderError.hostNotAllowed("api.openai.com.example.com")) {
            try await http.get(URL(string: "https://api.openai.com.example.com/")!, headers: [:])
        }
    }

    @Test func refusesPlainHTTP() async {
        await #expect(throws: ProviderError.hostNotAllowed("api.deepseek.com")) {
            try await HTTPClient().get(URL(string: "http://api.deepseek.com/user/balance")!, headers: [:])
        }
    }

    @Test func refusesLineBreaksInHeaders() async {
        await #expect(throws: ProviderError.self) {
            try await HTTPClient().get(URL(string: "https://api.deepseek.com/user/balance")!,
                                       headers: ["Authorization": "Bearer abc\r\nX-Evil: 1"])
        }
    }

    @Test func csvFieldsAreQuotedAndDefused() {
        #expect(History.csvField("meter.claude.session") == "\"meter.claude.session\"")
        #expect(History.csvField("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(History.csvField("a,b") == "\"a,b\"")
    }

    @Test func historyFileIsOwnerOnly() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("history.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try History(url: url)
        let fileMode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        let dirMode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(fileMode == 0o600)
        #expect(dirMode == 0o700)
    }

    /// Live check: openrouter.ai/docs answers 308. The client must stop there instead of following it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QUOTA_NETWORK_TESTS"] == "1"))
    func doesNotFollowRedirects() async {
        await #expect(throws: ProviderError.http(308)) {
            try await HTTPClient().get(URL(string: "https://openrouter.ai/docs")!, headers: [:])
        }
    }
}
