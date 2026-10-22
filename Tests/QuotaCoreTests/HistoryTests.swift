import Foundation
import Testing
@testable import QuotaCore

@Suite struct HistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    @Test func spentIgnoresTopUps() {
        let s = [10.0, 9, 20, 18.5].enumerated().map { History.Sample(at: t0 + Double($0) * 100, value: $1) }
        #expect(History.spent(s, since: t0 + 50) == 2.5)  // 10→9 (1) + top-up ignored + 20→18.5 (1.5)
        #expect(History.spent(s, since: t0 + 250) == 1.5)
    }

    @Test func spentUsesSampleBeforeWindow() {
        let s = [History.Sample(at: t0 + 100, value: 8)]
        #expect(History.spent(s, since: t0 + 50, previous: .init(at: t0, value: 10)) == 2)
    }

    @Test func recordsDedupesAndExportsAndDeletes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let history = try History(url: url)

        await history.record(.deepSeek, metric: "stat.x", value: 5, at: t0)
        await history.record(.deepSeek, metric: "stat.x", value: 5, at: t0 + 60)      // unchanged, too soon: skipped
        await history.record(.deepSeek, metric: "stat.x", value: 4, at: t0 + 120)     // changed: stored
        await history.record(.deepSeek, metric: "stat.x", value: 4, at: t0 + 120 + History.unchangedInterval) // stale: stored

        let series = await history.series(.deepSeek, metric: "stat.x", since: t0)
        #expect(series.map(\.value) == [5, 4, 4])
        #expect(await history.exportCSV().split(separator: "\n").count == 4)

        await history.deleteAll()
        #expect(await history.series(.deepSeek, metric: "stat.x", since: t0).isEmpty)
    }
}
