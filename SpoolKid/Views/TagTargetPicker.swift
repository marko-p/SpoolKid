//
//  TagTargetPicker.swift
//  SpoolKid
//
//  Purpose: Where a tag goes — a spool, or, where filament links are
//  written, a filament (spec 2026-10-11). Shows ranked spool candidates
//  without confidence percentages; the user can also search all spools and
//  all filaments.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

/// What the picker picked.
enum TagTarget {
    case spool(Spool)
    case filament(Filament)
}

/// The Filaments tab's input. Nil keeps the picker spools-only.
nonisolated struct FilamentTargets: Equatable, Sendable {
    let suggestedIDs: [Int]
    let excludedIDs: Set<Int>
}

struct TagTargetPicker: View {
    private enum Tab: Hashable {
        case spools, filaments
    }

    let matches: [FilamentMatchResult]
    var allowAllSpools: Bool = false
    var excludedSpoolIDs: Set<Int> = []
    /// D5 (spec 2026-09-27): Transfer Tag's tag-move offer. Nil for the link
    /// and write-onto-tag choosers.
    var tagMoveOffer: TagMoveOffer? = nil
    /// Spec 2026-10-11: set for Transfer Tag and Link Tag… where filament
    /// links are written. Nil hides the Filaments tab.
    var filamentTargets: FilamentTargets? = nil
    /// `movedTagUIDs` is the ticked part of `tagMoveOffer`, empty without one.
    var onSelect: (TagTarget, _ movedTagUIDs: [String]) -> Void

    @EnvironmentObject private var store: SpoolDataStore

    @State private var searchText = ""
    @State private var tab: Tab = .spools
    @State private var movingTagUIDs: Set<String> = []
    @State private var didSeedTagSelection = false
    @Environment(\.dismiss) private var dismiss

    // MARK: - Filtered candidates

    private var filteredMatches: [FilamentMatchResult] {
        matches.filter { m in
            let filament = m.spool.filament
            return SearchQuery.matches(searchText, in: [
                filament.name, filament.vendor?.name, filament.material,
                String(m.spool.id)
            ])
        }
    }

    private var searchAllResults: [Spool] {
        guard allowAllSpools || (!searchText.isEmpty && searchText.count >= 2) else { return [] }
        let candidateIDs = Set(matches.map { $0.spool.id }).union(excludedSpoolIDs)
        return store.activeSpools.filter { spool in
            guard !candidateIDs.contains(spool.id) else { return false }

            if allowAllSpools && searchText.isEmpty {
                return true
            }

            let filament = spool.filament
            return SearchQuery.matches(searchText, in: [
                filament.name, filament.vendor?.name, filament.material,
                String(spool.id)
            ])
        }
    }

    private func filamentMatchesSearch(_ filament: Filament) -> Bool {
        SearchQuery.matches(searchText, in: [filament.listTitle, filament.vendor?.name, filament.material])
    }

    static func mappedTagDisclosureText(for spool: Spool) -> String? {
        let mappedUIDs = spool.mappedCardUIDs
        guard !mappedUIDs.isEmpty else { return nil }
        return "Mapped tags (will be overwritten): \(mappedUIDs.joined(separator: ", "))"
    }

    /// A transfer with nothing ticked would move nothing; the rows wait for
    /// at least one tag.
    nonisolated static func selectionBlocked(offer: TagMoveOffer?, selection: Set<String>) -> Bool {
        offer != nil && selection.isEmpty
    }

    /// The suggested filaments, in `ids` order: each one present in
    /// `filaments`, not excluded, and listed once.
    nonisolated static func suggestedFilaments(ids: [Int], excluded: Set<Int>, in filaments: [Filament]) -> [Filament] {
        var seen = Set<Int>()
        return ids.compactMap { id in
            guard !excluded.contains(id), seen.insert(id).inserted else { return nil }
            return filaments.first { $0.id == id }
        }
    }

    private var isSelectionBlocked: Bool {
        Self.selectionBlocked(offer: tagMoveOffer, selection: movingTagUIDs)
    }

    private var movedTagUIDs: [String] {
        tagMoveOffer?.movedUIDs(selection: movingTagUIDs) ?? []
    }

    // MARK: - Body

    var body: some View {
        HarmonizedSearchList(
            title: filamentTargets == nil ? "Choose Spool" : "Choose Spool or Filament",
            searchText: $searchText,
            prompt: filamentTargets == nil ? "Search spools" : "Search"
        ) {
            if let offer = tagMoveOffer {
                tagChecklist(offer)
            }

            if filamentTargets != nil {
                Section {
                    Picker("Target", selection: $tab) {
                        Text("Spools").tag(Tab.spools)
                        Text("Filaments").tag(Tab.filaments)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if tab == .filaments, let targets = filamentTargets {
                filamentSections(targets)
            } else {
                spoolSections
            }
        }
        .task {
            if !didSeedTagSelection, let offer = tagMoveOffer {
                movingTagUIDs = offer.defaultSelection
                didSeedTagSelection = true
            }
            if store.spools.isEmpty {
                await store.fetchSpools()
            }
            if filamentTargets != nil, store.filaments.isEmpty {
                await store.fetchFilaments()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func tagChecklist(_ offer: TagMoveOffer) -> some View {
        Section {
            ForEach(offer.uids, id: \.self) { uid in
                Toggle(isOn: Binding(
                    get: { movingTagUIDs.contains(uid) },
                    set: { isOn in
                        if isOn { movingTagUIDs.insert(uid) } else { movingTagUIDs.remove(uid) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uid)
                            .font(.body.monospaced())
                        if uid == offer.scannedUID {
                            Text("Scanned")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Move Tags from \(offer.sourceTitle)")
        } footer: {
            Text(isSelectionBlocked
                 ? "Tick at least one tag to move."
                 : filamentTargets == nil
                    ? "Ticked tags move to the spool you choose and are removed from \(offer.sourceTitle)."
                    : "Ticked tags move to the spool or filament you choose and are removed from \(offer.sourceTitle).")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var spoolSections: some View {
        if !filteredMatches.isEmpty {
            Section("Candidates") {
                ForEach(filteredMatches, id: \.spool.id) { match in
                    Button {
                        onSelect(.spool(match.spool), movedTagUIDs)
                        dismiss()
                    } label: {
                        matchRow(match: match)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelectionBlocked)
                }
            }
        } else if !searchText.isEmpty {
            Section {
                Text("No candidates match \"\(searchText)\".")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }

        if !searchAllResults.isEmpty {
            Section(allowAllSpools && searchText.isEmpty ? "All Spools" : "All Spools (search results)") {
                ForEach(searchAllResults) { spool in
                    Button {
                        onSelect(.spool(spool), movedTagUIDs)
                        dismiss()
                    } label: {
                        spoolRow(spool: spool)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelectionBlocked)
                }
            }
        }
    }

    @ViewBuilder
    private func filamentSections(_ targets: FilamentTargets) -> some View {
        let suggested = Self.suggestedFilaments(ids: targets.suggestedIDs, excluded: targets.excludedIDs, in: store.filaments)
        let suggestedIDs = Set(suggested.map { $0.id })
        let shownSuggested = suggested.filter(filamentMatchesSearch)
        let others = store.filaments
            .filter { !targets.excludedIDs.contains($0.id) && !suggestedIDs.contains($0.id) && filamentMatchesSearch($0) }
            .sorted { $0.listTitle.localizedCaseInsensitiveCompare($1.listTitle) == .orderedAscending }

        if !shownSuggested.isEmpty {
            Section("Suggested") {
                ForEach(shownSuggested) { filament in filamentButton(filament) }
            }
        }
        if !others.isEmpty {
            Section("All Filaments") {
                ForEach(others) { filament in filamentButton(filament) }
            }
        } else if shownSuggested.isEmpty {
            Section {
                Text("No filaments match.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Subviews

    private func filamentButton(_ filament: Filament) -> some View {
        Button {
            onSelect(.filament(filament), movedTagUIDs)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                FilamentSwatch(colors: filament.colors, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filament.listTitle)
                        .font(.headline)
                        .lineLimit(1)
                    let detail = FilamentTagCard.detail(for: filament)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelectionBlocked)
    }

    @ViewBuilder
    private func matchRow(match: FilamentMatchResult) -> some View {
        HStack(spacing: 12) {
            FilamentSwatch(colors: match.spool.filament.colors, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.spool.listTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(match.spool.listDetailParts.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if match.brandMismatch {
                    Text("Brand mismatch — capped at 79%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let mappedTagDisclosure = Self.mappedTagDisclosureText(for: match.spool) {
                    Text(mappedTagDisclosure)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func spoolRow(spool: Spool) -> some View {
        HStack(spacing: 12) {
            FilamentSwatch(colors: spool.filament.colors, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(spool.listTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(spool.listDetailParts.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let mappedTagDisclosure = Self.mappedTagDisclosureText(for: spool) {
                    Text(mappedTagDisclosure)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
