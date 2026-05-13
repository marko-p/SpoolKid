//
//  NewSpoolFilamentSelectionView.swift
//  SpoolKid
//
//  Purpose: Lets user choose an alternative filament candidate
//  for creating a new spool from Scan Result Hub.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the MIT License.
// See LICENSE in the project root for details.
//

import SwiftUI

struct NewSpoolFilamentSelectionView: View {
    let candidates: [ScanResultHubView.NewSpoolSource]
    let onSelect: (ScanResultHubView.NewSpoolSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredCandidates: [ScanResultHubView.NewSpoolSource] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        let lower = query.lowercased()

        return candidates.filter { candidate in
            searchableText(for: candidate).contains(lower)
        }
    }

    var body: some View {
        List {
            Section("Filament Candidates") {
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
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search filaments")
        .navigationTitle("Choose Filament")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func candidateRow(_ candidate: ScanResultHubView.NewSpoolSource) -> some View {
        HStack(spacing: 12) {
            colorSwatch(for: candidate)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: candidate))
                    .font(.headline)
                    .lineLimit(1)

                ForEach(detailLines(for: candidate), id: \.self) { detail in
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(sourceLabel(for: candidate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func colorSwatch(for candidate: ScanResultHubView.NewSpoolSource) -> some View {
        let hex: String? = switch candidate {
        case .local(let filament):
            filament.colorHex
        case .spoolmanDB(let filament):
            filament.colorHex
        }

        Circle()
            .fill(hex.flatMap { Color(hex: $0) } ?? .gray)
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
    }

    private func title(for candidate: ScanResultHubView.NewSpoolSource) -> String {
        switch candidate {
        case .local(let filament):
            return filament.name ?? "Unnamed Filament"
        case .spoolmanDB(let filament):
            return filament.name
        }
    }

    private func detailLines(for candidate: ScanResultHubView.NewSpoolSource) -> [String] {
        switch candidate {
        case .local(let filament):
            var lines: [String] = []
            lines.append("\(filament.vendor?.name ?? "Unknown Vendor") \(filament.material ?? "")")

            var specs: [String] = []
            if let diameter = filament.diameter {
                specs.append(String(format: "%.2f mm", diameter))
            }
            if let density = filament.density {
                specs.append(String(format: "%.2f g/cm³", density))
            }
            if !specs.isEmpty {
                lines.append(specs.joined(separator: " • "))
            }

            return lines

        case .spoolmanDB(let filament):
            var lines: [String] = []
            lines.append("\(filament.manufacturer) \(filament.material)")

            var specs: [String] = []
            specs.append(String(format: "%.2f mm", filament.diameter))
            specs.append(String(format: "%.2f g/cm³", filament.density))
            if let weight = filament.weight {
                specs.append(String(format: "%.0f g filament", weight))
            }
            if let spoolWeight = filament.spoolWeight {
                specs.append(String(format: "%.0f g spool", spoolWeight))
            }
            if let spoolType = filament.spoolType, !spoolType.isEmpty {
                specs.append(spoolType)
            }
            if !specs.isEmpty {
                lines.append(specs.joined(separator: " • "))
            }

            return lines
        }
    }

    private func sourceLabel(for candidate: ScanResultHubView.NewSpoolSource) -> String {
        switch candidate {
        case .local:
            return "From My Filaments"
        case .spoolmanDB:
            return "From SpoolmanDB (will import first)"
        }
    }

    private func searchableText(for candidate: ScanResultHubView.NewSpoolSource) -> String {
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
                String(format: "%.2f", filament.density),
                filament.weight.map { String(format: "%.0f", $0) } ?? "",
                filament.spoolWeight.map { String(format: "%.0f", $0) } ?? "",
                "spoolmandb"
            ]
            .joined(separator: " ")
            .lowercased()
        }
    }
}
