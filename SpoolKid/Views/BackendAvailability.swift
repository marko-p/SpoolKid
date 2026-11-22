//
//  BackendAvailability.swift
//  SpoolKid
//
//  Purpose: One backend-agnostic, SwiftUI-reactive answer to "is the ACTIVE
//  backend's library usable right now?" — the consumer for
//  `BackendCapabilities.connectionValidKey`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.spoolkid", category: "BackendAvailability")

/// What a `BackendAvailability` reader could determine about one backend's
/// validated-connection flag.
///
/// The third case is the point of the type. Folding it into `false` would make
/// a wiring defect indistinguishable from a user who simply has not connected
/// yet — the same conflation that let the Library tab tell FilaMan users to
/// configure Spoolman.
nonisolated enum BackendConnectionFlag: Equatable {
    /// The backend declares no flag: its rows are on the device and there is
    /// nothing to validate.
    case notApplicable
    /// The backend's own flag, as stored.
    case read(Bool)
    /// The backend declares a flag key this reader has no `@AppStorage` for —
    /// a wiring defect, not a connection problem.
    case unreadable(key: String)
}

/// Reactive read of whichever backend's validated-connection flag applies.
///
/// Until 2026-08-22 five views declared
/// `@AppStorage(AppConfig.spoolmanConnectionValidKey)` and gated their whole
/// contents on it. That is backend-identity coupling wearing a storage key
/// instead of a `kind ==` comparison: FilaMan writes
/// `filaman_connection_valid`, so on a FilaMan-only install the flag those
/// views read was never set and both the Library tab and the Home dashboard
/// rendered "No Spoolman Connection" over a perfectly healthy server (F34).
///
/// `@AppStorage` binds its key at initialisation, while a view learns which
/// backend it is rendering only at body time (from `SpoolDataStore`), so the
/// key cannot simply be handed in. Every backend's flag is therefore declared
/// here once and selected by `BackendCapabilities.connectionValidKey` when
/// read — a new backend touches this file and nothing else.
///
/// `DynamicProperty` is what makes it reactive: SwiftUI installs the nested
/// `@AppStorage` properties and re-renders the host view when either flag
/// changes, exactly as declaring them in the view did.
struct BackendAvailability: DynamicProperty {
    @AppStorage private var spoolmanConnectionValid: Bool
    @AppStorage private var filaManConnectionValid: Bool

    /// `store: nil` uses the app's default store; tests pass their own suite so
    /// flipping a flag cannot race another test reading `UserDefaults.standard`.
    init(store: UserDefaults? = nil) {
        _spoolmanConnectionValid = AppStorage(
            wrappedValue: false, AppConfig.spoolmanConnectionValidKey, store: store
        )
        _filaManConnectionValid = AppStorage(
            wrappedValue: false, AppConfig.filamanConnectionValidKey, store: store
        )
    }

    /// Every connection flag this reader can see, by the key a backend declares.
    /// A backend whose `connectionValidKey` is missing here reads as
    /// `.unreadable` rather than as `false`;
    /// `BackendAvailabilityTests.everyBackendsConnectionFlagIsActuallyReadable`
    /// fails the build before that can ship.
    private var flagsByKey: [String: Bool] {
        [
            AppConfig.spoolmanConnectionValidKey: spoolmanConnectionValid,
            AppConfig.filamanConnectionValidKey: filaManConnectionValid
        ]
    }

    func connectionFlag(for capabilities: BackendCapabilities) -> BackendConnectionFlag {
        guard let key = capabilities.connectionValidKey else { return .notApplicable }
        guard let value = flagsByKey[key] else { return .unreadable(key: key) }
        return .read(value)
    }

    /// Whether the backend's library should render its contents rather than its
    /// "configure this backend" prompt.
    func isAvailable(_ capabilities: BackendCapabilities) -> Bool {
        let flag = connectionFlag(for: capabilities)
        if case .unreadable(let key) = flag {
            // A view has to show something, so it shows the conservative state —
            // but never silently, because no amount of connecting will fix this.
            logger.error(
                "Backend \(capabilities.kind.rawValue, privacy: .public) declares connection flag '\(key, privacy: .public)' that BackendAvailability cannot read; treating its library as unavailable."
            )
        }
        return Self.isAvailable(flag)
    }

    /// The pure decision, split out so every branch — including the one no
    /// shipping backend takes — is directly testable.
    nonisolated static func isAvailable(_ flag: BackendConnectionFlag) -> Bool {
        switch flag {
        case .notApplicable: return true
        case .read(let valid): return valid
        case .unreadable: return false
        }
    }
}
