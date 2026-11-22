import Foundation
import os.log

private nonisolated let logger = Logger(subsystem: "com.spoolkid", category: "OCRVocabularyLoader")

nonisolated struct OCRVocabularyColorEntry: Codable, Equatable, Sendable {
    let phrase: String
    let hex: String
}

nonisolated struct OCRVocabularyBrandEntry: Codable, Equatable, Sendable {
    let name: String
}

nonisolated struct OCRVocabularyMaterialEntry: Codable, Equatable, Sendable {
    let name: String
    let key: String
    let inferredBedTemp: Int?
}

nonisolated struct OcrFilamentTempEntry: Codable, Equatable, Sendable {
    let brand: String
    let material: String
    let colorName: String
    let nozzleMin: Int?
    let nozzleMax: Int?
    let bedTemp: Int?
}

/// The four vocabulary lists in their on-disk shape: the bundle's, or a delta
/// derived from SpoolmanDB. The derivation lives in `OCRVocabularyDerivation.swift`
/// (the Swift twin of the script that builds the bundled lists).
nonisolated struct OCRVocabularyLists: Codable, Equatable, Sendable {
    var colorMap: [OCRVocabularyColorEntry]
    var brands: [OCRVocabularyBrandEntry]
    var materials: [OCRVocabularyMaterialEntry]
    var filamentTemps: [OcrFilamentTempEntry]

    static let empty = OCRVocabularyLists(colorMap: [], brands: [], materials: [], filamentTemps: [])
}

nonisolated struct OCRVocabulary: Sendable {
    let colorMap: [(phrase: String, hex: String)]
    let brands: [String]
    let materials: [(name: String, key: String, inferredBedTemp: Int?)]
    let filamentTemps: [OcrFilamentTempEntry]
    let colorPhraseIndex: [String: ColorPhraseEntry]
    let colorPhraseWordCounts: [Int]
}

nonisolated struct ColorPhraseEntry: Sendable {
    let hex: String
    let phrase: String
    let arrayIndex: Int
}

/// Builds the OCR vocabulary from the bundled lists plus a cached online delta
/// (`VocabularyRefreshService` writes it, `OCRVocabularyDerivation` derives it).
/// Bundled entries always win a key clash. Builds happen outside the lock.
nonisolated final class OCRVocabularyLoader: @unchecked Sendable {
    static let shared = OCRVocabularyLoader(
        deltaDirectory: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vocabulary", isDirectory: true)
    )
    static let deltaFileNames = [
        "OCRColorMap.json", "OCRBrandList.json", "OCRMaterialList.json", "OCRFilamentTemps.json",
    ]
    private static let normalizeRegex = try! NSRegularExpression(pattern: "[^a-z0-9]+", options: [])

    private let bundle: Bundle
    private let deltaDirectory: URL
    private var cached: OCRVocabulary?
    private var cachedBundleLists: OCRVocabularyLists?
    private var cachedMaterialNames: [String]?
    private var generation = 0
    private var appliedGeneration = 0
    private let lock = NSLock()

    init(bundle: Bundle = .main, deltaDirectory: URL) {
        self.bundle = bundle
        self.deltaDirectory = deltaDirectory
    }

    /// Where the delta files live; `VocabularyRefreshService` writes them here.
    var deltaDirectoryURL: URL { deltaDirectory }

    func vocabulary() -> OCRVocabulary {
        if let cached = locked({ cached }) { return cached }
        let vocab = build()
        return locked {
            if let cached { return cached }
            cached = vocab
            return vocab
        }
    }

    func preload() {
        if locked({ cached != nil }) { return }
        let vocab = build()
        locked { if cached == nil { cached = vocab } }
    }

    /// Rebuilds from disk and swaps the result in. Overlapping reloads: the one
    /// that started last wins, an older, slower build is dropped.
    func reload() {
        let gen = beginReload()
        commit(build(), generation: gen)
    }

    /// Takes the next generation under the lock and invalidates the material cache.
    func beginReload() -> Int {
        locked {
            generation += 1
            cachedMaterialNames = nil
            return generation
        }
    }

    /// Stores `vocab` unless a newer reload has already been applied.
    func commit(_ vocab: OCRVocabulary, generation gen: Int) {
        locked {
            guard gen > appliedGeneration else { return }
            appliedGeneration = gen
            cached = vocab
        }
    }

    /// The decoded bundle alone (no delta), cached after the first decode.
    func bundleLists() -> OCRVocabularyLists {
        if let lists = locked({ cachedBundleLists }) { return lists }
        let lists = Self.readLists(from: .bundle(bundle), only: nil)
        return locked {
            if let cachedBundleLists { return cachedBundleLists }
            cachedBundleLists = lists
            return lists
        }
    }

    /// Material names A to Z from the bundle and the delta; decodes only the
    /// material files, never the large temperatures file.
    func materialNames() -> [String] {
        if let names = locked({ cachedMaterialNames }) { return names }
        let gen = locked { generation }
        let only: Set<String> = ["OCRMaterialList.json"]
        let bundled = Self.readLists(from: .bundle(bundle), only: only).materials
        let delta = Self.readLists(from: .directory(deltaDirectory), only: only).materials
        var seen = Set<String>()
        var names: [String] = []
        for entry in bundled + delta where seen.insert(entry.key.lowercased()).inserted {
            names.append(entry.name)
        }
        names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        locked { if generation == gen { cachedMaterialNames = names } }
        return names
    }

    /// Bundle entries win a key clash. The colour map and materials come out
    /// longest phrase first, as the scanners expect.
    static func merge(bundle: OCRVocabularyLists, delta: OCRVocabularyLists) -> OCRVocabularyLists {
        func union<T>(_ a: [T], _ b: [T], key: (T) -> String) -> [T] {
            var seen = Set<String>()
            return (a + b).filter { seen.insert(key($0)).inserted }
        }
        func longestFirst<T>(_ items: [T], length: (T) -> Int) -> [T] {
            items.enumerated()
                .sorted {
                    let (l, r) = (length($0.element), length($1.element))
                    return l != r ? l > r : $0.offset < $1.offset
                }
                .map(\.element)
        }
        let colors = union(bundle.colorMap, delta.colorMap) { normalizeColorPhrase($0.phrase) }
        let materials = union(bundle.materials, delta.materials) { $0.key.lowercased() }
        return OCRVocabularyLists(
            colorMap: longestFirst(colors) { $0.phrase.count },
            brands: longestFirst(union(bundle.brands, delta.brands) { $0.name.lowercased() }) { $0.name.count },
            materials: longestFirst(materials) { $0.name.count },
            filamentTemps: union(bundle.filamentTemps, delta.filamentTemps) {
                "\($0.brand.lowercased())|\($0.material.uppercased())|\($0.colorName.lowercased())"
            }
        )
    }

    static func normalizeColorPhrase(_ text: String) -> String {
        let lower = text.lowercased()
        let range = NSRange(lower.startIndex..., in: lower)
        let replaced = normalizeRegex.stringByReplacingMatches(
            in: lower,
            range: range,
            withTemplate: " "
        )
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func locked<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func build() -> OCRVocabulary {
        let merged = Self.merge(
            bundle: bundleLists(),
            delta: Self.readLists(from: .directory(deltaDirectory), only: nil)
        )
        return Self.makeVocabulary(merged)
    }

    private enum Source {
        case bundle(Bundle)
        case directory(URL)

        func data(_ fileName: String) -> Data? {
            switch self {
            case .bundle(let bundle):
                let name = (fileName as NSString).deletingPathExtension
                guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
                return try? Data(contentsOf: url)
            case .directory(let url):
                return try? Data(contentsOf: url.appendingPathComponent(fileName))
            }
        }
    }

    /// Each file decodes on its own: a missing or corrupt one yields an empty list.
    private static func readLists(from source: Source, only: Set<String>?) -> OCRVocabularyLists {
        func read<T: Decodable>(_ fileName: String, as type: T.Type) -> [T] {
            if let only, !only.contains(fileName) { return [] }
            guard let data = source.data(fileName) else {
                if case .bundle = source { logger.error("\(fileName) not found in bundle") }
                return []
            }
            do {
                return try JSONDecoder().decode([T].self, from: data)
            } catch {
                logger.error("Failed to decode \(fileName): \(error.localizedDescription)")
                return []
            }
        }
        return OCRVocabularyLists(
            colorMap: read("OCRColorMap.json", as: OCRVocabularyColorEntry.self),
            brands: read("OCRBrandList.json", as: OCRVocabularyBrandEntry.self),
            materials: read("OCRMaterialList.json", as: OCRVocabularyMaterialEntry.self),
            filamentTemps: read("OCRFilamentTemps.json", as: OcrFilamentTempEntry.self)
        )
    }

    private static func makeVocabulary(_ lists: OCRVocabularyLists) -> OCRVocabulary {
        let colorMap = lists.colorMap.map { ($0.phrase, $0.hex) }
        var colorPhraseIndex: [String: ColorPhraseEntry] = [:]
        var wordCountSet = Set<Int>()
        for (index, entry) in colorMap.enumerated() {
            let normalized = normalizeColorPhrase(entry.0)
            let tokens = normalized.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }
            let key = tokens.joined(separator: " ")
            wordCountSet.insert(tokens.count)
            if colorPhraseIndex[key] == nil {
                colorPhraseIndex[key] = ColorPhraseEntry(hex: entry.1, phrase: entry.0, arrayIndex: index)
            }
        }
        return OCRVocabulary(
            colorMap: colorMap,
            brands: lists.brands.map(\.name),
            materials: lists.materials.map { ($0.name, $0.key, $0.inferredBedTemp) },
            filamentTemps: lists.filamentTemps,
            colorPhraseIndex: colorPhraseIndex,
            colorPhraseWordCounts: wordCountSet.sorted(by: >)
        )
    }
}
