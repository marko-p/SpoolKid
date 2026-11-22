import Foundation
import os.log

private nonisolated let logger = Logger(subsystem: "com.spoolkid", category: "VocabularyRefresh")

/// Weekly refresh of the OCR vocabulary delta from the public SpoolmanDB, whatever
/// backend is active. Fetches and decodes both catalogues, derives the delta against
/// the bundle alone, then replaces the delta directory as one unit: the four files are
/// staged in a sibling directory and swapped in with `replaceItemAt`. Any failure
/// leaves the previous delta, its date and the loader's state untouched.
nonisolated struct VocabularyRefreshService: Sendable {
    static let interval: TimeInterval = 7 * 24 * 60 * 60
    static let filamentsURL = URL(string: "https://donkie.github.io/SpoolmanDB/filaments.json")!
    /// A catalogue smaller than this is treated as a bad response (SpoolmanDB has ~10,000).
    static let minimumFilamentCount = 1000
    static let materialsURL = URL(string: "https://donkie.github.io/SpoolmanDB/materials.json")!

    private let fetch: @Sendable (URL) async throws -> Data
    // Used only from `refreshIfDue`, one call at a time per launch.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let loader: OCRVocabularyLoader
    private let now: @Sendable () -> Date
    private let write: @Sendable (Data, URL) throws -> Void

    init(
        fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(for: request(for: $0)).0 },
        defaults: UserDefaults = .standard,
        loader: OCRVocabularyLoader = .shared,
        now: @escaping @Sendable () -> Date = Date.init,
        write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }
    ) {
        self.fetch = fetch
        self.defaults = defaults
        self.loader = loader
        self.now = now
        self.write = write
    }

    /// Wi-Fi or wired only (owner, 2026-11-21): never mobile data or a personal
    /// hotspot, never in Low Data Mode. Blocked, the fetch fails like being
    /// offline, so nothing changes and the next launch tries again.
    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = false
        request.allowsExpensiveNetworkAccess = false
        request.allowsConstrainedNetworkAccess = false
        return request
    }

    /// False under unit tests (host app) and UI tests, which must not download or reload the vocabulary.
    static func shouldRun(environment: [String: String], arguments: [String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        return !arguments.contains(AppConfig.disableVocabularyRefreshArgument)
    }

    static func isDue(lastRefresh: Date?, now: Date) -> Bool {
        guard let lastRefresh else { return true }
        if lastRefresh > now { return true }
        return now.timeIntervalSince(lastRefresh) >= interval
    }

    /// True only when new delta files were written and loaded.
    @discardableResult
    func refreshIfDue() async -> Bool {
        let current = now()
        let last = defaults.object(forKey: AppConfig.vocabularyLastRefreshKey) as? Date
        guard Self.isDue(lastRefresh: last, now: current) else { return false }

        let encoded: [(name: String, data: Data)]
        do {
            let filaments = try JSONDecoder().decode([SpoolmanDBFilament].self, from: try await fetch(Self.filamentsURL))
            guard filaments.count >= Self.minimumFilamentCount else {
                logger.error("Vocabulary refresh refused a catalogue of \(filaments.count, privacy: .public) filaments")
                return false
            }
            let materials = try JSONDecoder().decode([SpoolmanDBMaterial].self, from: try await fetch(Self.materialsURL))
            let lists = OCRVocabularyDerivation.delta(
                filaments: filaments,
                materials: materials,
                bundle: loader.bundleLists()
            )
            let encoder = JSONEncoder()
            encoded = [
                (OCRVocabularyLoader.deltaFileNames[0], try encoder.encode(lists.colorMap)),
                (OCRVocabularyLoader.deltaFileNames[1], try encoder.encode(lists.brands)),
                (OCRVocabularyLoader.deltaFileNames[2], try encoder.encode(lists.materials)),
                (OCRVocabularyLoader.deltaFileNames[3], try encoder.encode(lists.filamentTemps)),
            ]
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            logger.error("Vocabulary refresh failed before writing: \(error.localizedDescription, privacy: .public)")
            return false
        }

        do {
            try swapInDelta(encoded)
        } catch {
            logger.error("Vocabulary refresh could not write delta: \(error.localizedDescription, privacy: .public)")
            return false
        }

        excludeDeltaFromBackup()
        defaults.set(current, forKey: AppConfig.vocabularyLastRefreshKey)
        loader.reload()
        return true
    }

    /// Writes all four files into a staging directory beside the delta directory, then
    /// swaps it in as one unit. If staging fails, the old delta is never touched; if the
    /// swap fails, `replaceItemAt` leaves the original in place. The staging directory
    /// is removed on every failure path.
    private func swapInDelta(_ files: [(name: String, data: Data)]) throws {
        let directory = loader.deltaDirectoryURL
        let parent = directory.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        removeStaleStaging(in: parent)
        let staging = parent.appendingPathComponent(".VocabularyStaging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for file in files {
                try write(file.data, staging.appendingPathComponent(file.name))
            }
            if fm.fileExists(atPath: directory.path) {
                _ = try fm.replaceItemAt(directory, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: directory)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Best effort: staging directories left by an interrupted refresh.
    private func removeStaleStaging(in parent: URL) {
        let fm = FileManager.default
        do {
            let names = try fm.contentsOfDirectory(atPath: parent.path)
            for name in names where name.hasPrefix(".VocabularyStaging-") {
                do { try fm.removeItem(at: parent.appendingPathComponent(name)) } catch {
                    logger.error("Could not remove stale staging \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            logger.error("Could not list vocabulary parent: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The delta is re-downloadable, so keep it out of backups. Not fatal on failure.
    private func excludeDeltaFromBackup() {
        var url = loader.deltaDirectoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do { try url.setResourceValues(values) } catch {
            logger.error("Could not exclude vocabulary delta from backup: \(error.localizedDescription, privacy: .public)")
        }
    }
}
