//
//  SpoolMatchSelectionView.swift
//  SpoolKid
//
//  Purpose: Full candidate list for manual spool mapping.
//  Shows ranked matches without confidence percentages. User can also search all spools.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct SpoolMatchSelectionView: View {
    let matches: [FilamentMatchResult]
    var allowAllSpools: Bool = false
    var excludedSpoolIDs: Set<Int> = []
    var onSelect: (SpoolmanSpool) -> Void

    @StateObject private var spoolmanService = SpoolmanService()
    @AppStorage(AppConfig.spoolmanUrlKey) private var spoolmanUrl: String = AppConfig.defaultSpoolmanUrl

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    // MARK: - Filtered candidates

    private var filteredMatches: [FilamentMatchResult] {
        guard !searchText.isEmpty else { return matches }
        let q = searchText.lowercased()
        return matches.filter { m in
            let filament = m.spool.filament
            return (filament.name ?? "").lowercased().contains(q)
                || (filament.vendor?.name ?? "").lowercased().contains(q)
                || (filament.material ?? "").lowercased().contains(q)
                || String(m.spool.id).contains(q)
        }
    }

    private var searchAllResults: [SpoolmanSpool] {
        guard allowAllSpools || (!searchText.isEmpty && searchText.count >= 2) else { return [] }
        let q = searchText.lowercased()
        let candidateIDs = Set(matches.map { $0.spool.id }).union(excludedSpoolIDs)
        return spoolmanService.spools.filter { spool in
            guard !candidateIDs.contains(spool.id) else { return false }

            if allowAllSpools && searchText.isEmpty {
                return true
            }

            let filament = spool.filament
            return (filament.name ?? "").lowercased().contains(q)
                || (filament.vendor?.name ?? "").lowercased().contains(q)
                || (filament.material ?? "").lowercased().contains(q)
                || String(spool.id).contains(q)
        }
    }

    static func spoolIDText(id: Int) -> String {
        "Spool #\(id)"
    }

    static func mappedTagDisclosureText(lotNr: String?) -> String? {
        let mappedUIDs = SpoolMappingService.cardUIDs(in: lotNr)
        guard !mappedUIDs.isEmpty else { return nil }
        return "Mapped tags (will be overwritten): \(mappedUIDs.joined(separator: ", "))"
    }

    // MARK: - Body

    var body: some View {
        List {
            if !filteredMatches.isEmpty {
                Section("Candidates") {
                    ForEach(filteredMatches, id: \.spool.id) { match in
                        Button {
                            onSelect(match.spool)
                            dismiss()
                        } label: {
                            matchRow(match: match)
                        }
                        .buttonStyle(.plain)
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
                            onSelect(spool)
                            dismiss()
                        } label: {
                            spoolRow(spool: spool)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search spools")
        .navigationTitle("Choose Spool")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if spoolmanService.spools.isEmpty {
                await spoolmanService.fetchSpools(baseUrl: spoolmanUrl)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func matchRow(match: FilamentMatchResult) -> some View {
        HStack(spacing: 12) {
            colorSwatch(hex: match.spool.filament.colorHex, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.spool.filament.name ?? "Spool #\(match.spool.id)")
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.spoolIDText(id: match.spool.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let vendor = match.spool.filament.vendor?.name {
                        Text(vendor)
                    }
                    if let material = match.spool.filament.material {
                        Text(material)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let breakdown = match.brandMismatch ? Optional("Brand mismatch — capped at 79%") : nil {
                    Text(breakdown)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let mappedTagDisclosure = Self.mappedTagDisclosureText(lotNr: match.spool.lotNr) {
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
    private func spoolRow(spool: SpoolmanSpool) -> some View {
        HStack(spacing: 12) {
            colorSwatch(hex: spool.filament.colorHex, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(spool.filament.name ?? "Spool #\(spool.id)")
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.spoolIDText(id: spool.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let vendor = spool.filament.vendor?.name {
                        Text(vendor)
                    }
                    if let material = spool.filament.material {
                        Text(material)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let mappedTagDisclosure = Self.mappedTagDisclosureText(lotNr: spool.lotNr) {
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
    private func colorSwatch(hex: String?, size: CGFloat) -> some View {
        Circle()
            .fill(hex.flatMap { Color(hex: $0) } ?? Color.gray)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
    }
}
