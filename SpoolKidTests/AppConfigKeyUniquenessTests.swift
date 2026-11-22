import Foundation
import Testing
@testable import SpoolKid

/// Every preferences key is an `AppConfig` constant (C1). These checks read the
/// declarations straight out of `AppConfig.swift`, so a key added there is
/// covered the moment it exists. The hand-kept `allSettingsKeys` list they
/// replaced (2026-09-24) had fallen 14 keys behind — `backendKindKey` and every
/// FilaMan and TigerTag key among them — and nothing in the app read it:
/// Reset All Data clears the whole `UserDefaults` domain, not a list.
struct AppConfigKeyUniquenessTests {

    /// `name → value` for every `static let …Key = "…"` in AppConfig.swift.
    private static func declaredKeys() throws -> [(name: String, value: String)] {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SpoolKid/Services/AppConfig.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let pattern = /static let (\w+Key)\s*=\s*"([^"]*)"/
        return text.matches(of: pattern).map { (String($0.1), String($0.2)) }
    }

    @Test func theSourceScanFindsTheKeys() throws {
        let names = try Self.declaredKeys().map(\.name)
        // A scan that silently matched nothing would pass every check below.
        #expect(names.count > 100)
        #expect(names.contains("backendKindKey"))
        #expect(names.contains("authTokenKey"))
    }

    @Test func noTwoKeysShareAValue() throws {
        let values = try Self.declaredKeys().map(\.value)
        let duplicates = Dictionary(grouping: values, by: { $0 }).filter { $0.value.count > 1 }.keys
        #expect(duplicates.isEmpty, "Duplicate keys: \(duplicates.sorted())")
    }

    @Test func noEmptyKeys() throws {
        for key in try Self.declaredKeys() {
            #expect(!key.value.isEmpty, "\(key.name) is empty")
        }
    }

    @Test func rememberLastToggleKeysAbsent() throws {
        // The "Remember last spool/filament data" toggles were removed (behavior is always-on).
        // Guard against reintroducing a user-facing knob for always-on behavior.
        let values = try Self.declaredKeys().map(\.value)
        for key in ["remember_spool_data", "remember_filament_data"] {
            #expect(!values.contains(key), "Removed toggle key \(key) is declared again")
        }
    }

    @Test func supportKeysUseTheSupportPrefix() throws {
        // "donation" means TipKit event donation in this codebase. Nothing in
        // this feature may borrow the word.
        for key in try Self.declaredKeys().map(\.value) where key.hasPrefix("support_") {
            #expect(!key.contains("donat"), "\(key) uses the reserved TipKit vocabulary")
        }
    }
}
