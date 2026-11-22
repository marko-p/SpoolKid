//
//  NewSpoolFilamentSelectionView.swift
//  SpoolKid
//
//  Purpose: Lets user choose an alternative filament candidate
//  for creating a new spool from Scan Result Hub.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI

struct NewSpoolFilamentSelectionView: View {
    /// Loads the candidates when the list opens (and again on Retry): on
    /// FilaMan that is a few requests, which the hub does not pay for scans
    /// that never open this list.
    let load: () async -> ScanResolutionService.CandidateLoad
    let onSelect: (ScanResolutionService.NewSpoolSource) -> Void
    /// The catalogue the candidates come from, as the rows name it.
    var catalogName = "SpoolmanDB"

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var candidates: [ScanResolutionService.NewSpoolSource] = []
    /// How the catalogue answered the last load; nil while one is running.
    @State private var catalogue: ScanResolutionService.CatalogueAnswer?
    /// Bumped by Retry; the load task is keyed on it.
    @State private var attempt = 0

    private var filteredCandidates: [ScanResolutionService.NewSpoolSource] {
        candidates.filter { candidate in
            SearchQuery.matches(searchText, in: [searchableText(for: candidate)])
        }
    }

    var body: some View {
        HarmonizedSearchList(title: "Choose Filament", searchText: $searchText, prompt: "Search filaments") {
            Section("Filament Candidates") {
                catalogueStatusRow
                ForEach(filteredCandidates) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        candidateRow(candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: attempt) {
            catalogue = nil
            let loaded = await load()
            // A closed or restarted load is not an answer.
            guard !Task.isCancelled else { return }
            candidates = loaded.candidates
            catalogue = loaded.catalogue
        }
    }

    /// Says what the catalogue is doing, so a missing answer is never read as
    /// "nothing found": loading, could not reach (with Retry), or no filaments
    /// for this brand. The local candidates below stand in every case.
    @ViewBuilder
    private var catalogueStatusRow: some View {
        switch catalogue {
        case nil:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .failed:
            HStack(spacing: 12) {
                Label("Could not reach \(catalogName)", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                Spacer()
                Button("Retry") { attempt += 1 }
                    .buttonStyle(.bordered)
            }
        case .noBrand:
            Text("\(catalogName) has no filaments for this brand.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .answered:
            EmptyView()
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: ScanResolutionService.NewSpoolSource) -> some View {
        HStack(spacing: 12) {
            colorSwatch(for: candidate)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: candidate))
                    .font(.headline)
                    .lineLimit(1)

                Text(detailLine(for: candidate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(sourceLabel(for: candidate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func colorSwatch(for candidate: ScanResolutionService.NewSpoolSource) -> some View {
        let colors: FilamentColors = switch candidate {
        case .local(let filament):
            filament.colors
        case .spoolmanDB(let filament):
            filament.colors
        }

        FilamentSwatch(colors: colors, size: 26)
    }

    private func title(for candidate: ScanResolutionService.NewSpoolSource) -> String {
        switch candidate {
        case .local(let filament):
            return filament.listTitle
        case .spoolmanDB(let filament):
            return filament.listTitle
        }
    }

    private func detailLine(for candidate: ScanResolutionService.NewSpoolSource) -> String {
        switch candidate {
        case .local(let filament):
            return filament.listSpecParts.joined(separator: " • ")
        case .spoolmanDB(let filament):
            return filament.listDetailParts.joined(separator: " • ")
        }
    }

    private func sourceLabel(for candidate: ScanResolutionService.NewSpoolSource) -> String {
        switch candidate {
        case .local:
            return "From My Filaments"
        case .spoolmanDB:
            return "From \(catalogName) (will import first)"
        }
    }

    private func searchableText(for candidate: ScanResolutionService.NewSpoolSource) -> String {
        switch candidate {
        case .local(let filament):
            return [
                filament.name ?? "",
                filament.vendor?.name ?? "",
                filament.material ?? "",
                filament.diameter.map { String(format: "%.2f", $0) } ?? "",
                filament.density.map { String(format: "%.2f", $0) } ?? "",
                "my filaments"
            ]
            .joined(separator: " ")
            .lowercased()
        case .spoolmanDB(let filament):
            return [
                filament.name,
                filament.manufacturer,
                filament.material,
                filament.spoolType ?? "",
                String(format: "%.2f", filament.diameter),
                filament.density.map { String(format: "%.2f", $0) } ?? "",
                filament.weight.map { String(format: "%.0f", $0) } ?? "",
                filament.spoolWeight.map { String(format: "%.0f", $0) } ?? "",
                catalogName.lowercased()
            ]
            .joined(separator: " ")
            .lowercased()
        }
    }
}
