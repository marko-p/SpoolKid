import Foundation
import Testing
@testable import SpoolKid

/// Each test gets its own UserDefaults suite and its own temp root (holding the delta
/// directory and any staging sibling); nothing touches `.standard` or
/// `OCRVocabularyLoader.shared`.
nonisolated struct VocabularyRefreshServiceTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    /// One recognisable filament plus enough padding to clear the minimum catalogue size.
    static let filamentsFixture: String = {
        let entry = { (id: String, name: String) in
            """
            {"id": "\(id)", "manufacturer": "Zyxbrand Test", "name": "\(name)", "material": "PLA",
             "spool_type": null, "density": 1.24, "weight": 1000, "spool_weight": 200,
             "diameter": 1.75, "color_hex": "FF0000", "extruder_temp": 210, "bed_temp": 60}
            """
        }
        let padding = (0..<VocabularyRefreshService.minimumFilamentCount).map { entry("p\($0)", "Pad \($0)") }
        return "[" + ([entry("t1", "Red")] + padding).joined(separator: ",") + "]"
    }()
    static let materialsFixture = """
    [{"material": "PETG-TEST", "density": 1.27, "extruder_temp": 240, "bed_temp": 80}]
    """

    /// Counts calls from any thread; the stub closures are `@Sendable`.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    struct Harness {
        let suiteName = "VocabularyRefreshServiceTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let root: URL
        let deltaDirectory: URL
        let loader: OCRVocabularyLoader

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("VocabularyRefreshTests-\(UUID().uuidString)", isDirectory: true)
            deltaDirectory = root.appendingPathComponent("Vocabulary", isDirectory: true)
            loader = OCRVocabularyLoader(deltaDirectory: deltaDirectory)
        }

        func service(
            fetch: @escaping @Sendable (URL) async throws -> Data,
            now: Date = VocabularyRefreshServiceTests.now,
            write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }
        ) -> VocabularyRefreshService {
            VocabularyRefreshService(fetch: fetch, defaults: defaults, loader: loader, now: { now }, write: write)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        func fileExists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: deltaDirectory.appendingPathComponent(name).path)
        }

        /// Every delta file's bytes, in `deltaFileNames` order (nil when absent).
        func snapshot() -> [Data?] {
            OCRVocabularyLoader.deltaFileNames.map {
                try? Data(contentsOf: deltaDirectory.appendingPathComponent($0))
            }
        }

        /// Writes a complete earlier delta whose brands file names `brand`.
        func seedDelta(brand: String) throws {
            try FileManager.default.createDirectory(at: deltaDirectory, withIntermediateDirectories: true)
            for name in OCRVocabularyLoader.deltaFileNames {
                let body = name == "OCRBrandList.json" ? #"[{"name":"\#(brand)"}]"# : "[]"
                try Data(body.utf8).write(to: deltaDirectory.appendingPathComponent(name))
            }
        }
    }

    static func goodFetch(_ url: URL) async throws -> Data {
        if url.lastPathComponent == "filaments.json" { return Data(filamentsFixture.utf8) }
        return Data(materialsFixture.utf8)
    }

    @Test func isDueRules() {
        #expect(VocabularyRefreshService.isDue(lastRefresh: nil, now: Self.now))
        #expect(!VocabularyRefreshService.isDue(lastRefresh: Self.now.addingTimeInterval(-6 * Self.day), now: Self.now))
        #expect(VocabularyRefreshService.isDue(lastRefresh: Self.now.addingTimeInterval(-7 * Self.day), now: Self.now))
        #expect(VocabularyRefreshService.isDue(lastRefresh: Self.now.addingTimeInterval(Self.day), now: Self.now))
    }

    @Test func notDueDoesNotFetch() async {
        let h = Harness()
        defer { h.cleanup() }
        h.defaults.set(Self.now.addingTimeInterval(-Self.day), forKey: AppConfig.vocabularyLastRefreshKey)
        let counter = Counter()
        let ran = await h.service(fetch: { _ in counter.bump(); return Data() }).refreshIfDue()
        #expect(!ran)
        #expect(counter.count == 0)
    }

    @Test func successWritesDeltaSetsDateAndReloads() async {
        let h = Harness()
        defer { h.cleanup() }
        let ran = await h.service(fetch: Self.goodFetch).refreshIfDue()
        #expect(ran)
        for name in OCRVocabularyLoader.deltaFileNames {
            #expect(h.fileExists(name))
        }
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date == Self.now)
        #expect(h.loader.vocabulary().brands.contains("Zyxbrand Test"))
    }

    @Test func htmlResponseChangesNothing() async {
        let h = Harness()
        defer { h.cleanup() }
        let ran = await h.service(fetch: { _ in Data("<html>Not found</html>".utf8) }).refreshIfDue()
        #expect(!ran)
        #expect(!h.fileExists(OCRVocabularyLoader.deltaFileNames[0]))
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) == nil)
    }

    @Test func networkErrorChangesNothing() async throws {
        let h = Harness()
        defer { h.cleanup() }
        try seedPreviousRefresh(h)
        let before = h.snapshot()
        let old = h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date

        let ran = await h.service(fetch: { _ in throw URLError(.notConnectedToInternet) }).refreshIfDue()

        #expect(!ran)
        #expect(h.snapshot() == before)
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date == old)
    }

    @Test func cancellationChangesNothing() async throws {
        let h = Harness()
        defer { h.cleanup() }
        try seedPreviousRefresh(h)
        let before = h.snapshot()
        let old = h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date

        let ran = await h.service(fetch: { _ in throw CancellationError() }, now: Self.now.addingTimeInterval(8 * Self.day))
            .refreshIfDue()

        #expect(!ran)
        #expect(h.snapshot() == before)
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date == old)
    }

    /// A write fails on the third file. The swap never starts, so the previous delta
    /// (bytes, date, and what the loader serves) must survive, and no staging
    /// directory may be left behind.
    @Test func failedStagedWriteLeavesPreviousDeltaDateAndLoaderUnchanged() async throws {
        let h = Harness()
        defer { h.cleanup() }
        try h.seedDelta(brand: "Old Brand Test")
        h.defaults.set(Self.now.addingTimeInterval(-8 * Self.day), forKey: AppConfig.vocabularyLastRefreshKey)
        h.loader.reload()
        #expect(h.loader.vocabulary().brands.contains("Old Brand Test"))
        let before = h.snapshot()
        let old = h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date

        let writes = Counter()
        let failingWrite: @Sendable (Data, URL) throws -> Void = { data, url in
            writes.bump()
            if writes.count == 3 { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url)
        }
        let ran = await h.service(fetch: Self.goodFetch, write: failingWrite).refreshIfDue()

        #expect(!ran)
        #expect(writes.count == 3)
        #expect(h.snapshot() == before)
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date == old)
        #expect(h.loader.vocabulary().brands.contains("Old Brand Test"))
        #expect(!h.loader.vocabulary().brands.contains("Zyxbrand Test"))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: h.root.path)
        #expect(siblings == ["Vocabulary"])
    }

    @Test func tinyCatalogueIsRefusedAndKeepsPreviousDelta() async throws {
        let h = Harness()
        defer { h.cleanup() }
        try seedPreviousRefresh(h)
        let before = h.snapshot()
        let old = h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date

        let ran = await h.service(fetch: { url in
            url.lastPathComponent == "filaments.json" ? Data("[]".utf8) : Data(Self.materialsFixture.utf8)
        }).refreshIfDue()

        #expect(!ran)
        #expect(h.snapshot() == before)
        #expect(h.defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date == old)
    }

    @Test func staleStagingDirectoryIsSweptOnRefresh() async throws {
        let h = Harness()
        defer { h.cleanup() }
        let stale = h.root.appendingPathComponent(".VocabularyStaging-old", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        let ran = await h.service(fetch: Self.goodFetch).refreshIfDue()

        #expect(ran)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func requestStaysOffMobileDataAndLowDataMode() {
        let request = VocabularyRefreshService.request(for: VocabularyRefreshService.filamentsURL)
        #expect(request.url == VocabularyRefreshService.filamentsURL)
        #expect(!request.allowsCellularAccess)
        #expect(!request.allowsExpensiveNetworkAccess)
        #expect(!request.allowsConstrainedNetworkAccess)
    }

    @Test func shouldRunRules() {
        #expect(VocabularyRefreshService.shouldRun(environment: [:], arguments: []))
        #expect(!VocabularyRefreshService.shouldRun(environment: ["XCTestConfigurationFilePath": "/x"], arguments: []))
        #expect(!VocabularyRefreshService.shouldRun(environment: [:], arguments: [AppConfig.disableVocabularyRefreshArgument]))
    }

    /// A delta from an earlier refresh, dated a week before `now`, so a refresh is due.
    private func seedPreviousRefresh(_ h: Harness) throws {
        try h.seedDelta(brand: "Earlier Brand Test")
        h.defaults.set(Self.now.addingTimeInterval(-8 * Self.day), forKey: AppConfig.vocabularyLastRefreshKey)
    }
}
