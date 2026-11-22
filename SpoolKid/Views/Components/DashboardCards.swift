//
//  DashboardCards.swift
//  SpoolKid
//
//  Purpose: Presentational cards for the Home dashboard. Each renders values
//  produced by `DashboardStatsService`; drill-down elements use value-based
//  `NavigationLink(SpoolFilter)` resolved by the host `HomeDashboardView`.
//

//
// Copyright (c) 2026 Marko Praprotnik. All rights reserved.
// Licensed under the GNU AGPL v3.0 only; commercial licenses: see COMMERCIAL.md.
// See LICENSE in the project root for details.
//

import SwiftUI
import TipKit

extension SpoolFillBucket {
    /// Draining-status palette for the proportional bar and legend.
    var color: Color {
        switch self {
        case .full: Color(red: 0.06, green: 0.43, blue: 0.34)     // deep teal #0F6E56
        case .normal: Color(red: 0.11, green: 0.62, blue: 0.46)   // teal #1D9E75
        case .low: Color(red: 0.94, green: 0.62, blue: 0.15)      // amber #EF9F27
        case .critical: Color(red: 0.85, green: 0.35, blue: 0.19) // coral #D85A30
        case .empty: Color(.systemGray)
        }
    }
}

/// Rounded card container matching the dashboard's grouped-surface style.
struct DashboardCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A card's title with the (i) that explains how the card counts
/// (`DashboardInfo`).
struct DashboardCardTitle: View {
    let title: String
    let info: [String]
    var introTip: (any Tip)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text(title).font(.headline)
            InfoButton(title: title, lines: info, introTip: introTip)
                // Keeps the 44-pt tap target without making the title row
                // taller than the headline beside it.
                .padding(.vertical, -11)
        }
    }
}

/// Spool Status — draining proportional bar + legend; each bucket drills into that filter.
struct SpoolStatusCard: View {
    let counts: [SpoolFillBucket: Int]
    /// The (i)'s one-time intro tip — this card is the one always shown.
    var introTip: (any Tip)? = nil
    private var total: Int { counts.values.reduce(0, +) }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DashboardCardTitle(title: "Spool status", info: DashboardInfo.spoolStatus, introTip: introTip)
                    Spacer()
                    Text("\(total) spool\(total == 1 ? "" : "s")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(SpoolFillBucket.allCases, id: \.self) { bucket in
                            let c = counts[bucket] ?? 0
                            if c > 0 {
                                bucket.color
                                    .frame(width: geo.size.width * CGFloat(c) / CGFloat(max(total, 1)))
                            }
                        }
                    }
                }
                .frame(height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if total == 0 {
                        Text("No fill data yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(SpoolFillBucket.allCases, id: \.self) { bucket in
                        NavigationLink(value: SpoolFilter.fillBucket(bucket)) {
                            VStack(spacing: 4) {
                                Text("\(counts[bucket] ?? 0)").font(.headline).foregroundStyle(bucket.color)
                                Text(bucket.title).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Tag Coverage — untagged / single / multi-tag counts; untagged drills into that filter.
struct TagCoverageCard: View {
    let coverage: TagCoverage

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardTitle(title: "Tag coverage", info: DashboardInfo.tagCoverage)
                HStack(spacing: 4) {
                    NavigationLink(value: SpoolFilter.untagged) {
                        column(coverage.untagged, "Untagged", coverage.untagged > 0 ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    column(coverage.single, "1 tag", .primary)
                    column(coverage.multi, "2+ tags", .primary)
                }
            }
        }
    }

    private func column(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Reorder Soon — filaments with fewer than 30 days of runway; grows with the list.
struct ReorderSoonCard: View {
    let items: [FilamentRunway]

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                DashboardCardTitle(title: "Reorder soon", info: DashboardInfo.reorderSoon)
                if items.isEmpty {
                    Text("Nothing to reorder soon.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        NavigationLink(value: SpoolFilter.filament(item.filamentId)) { row(item) }
                            .buttonStyle(.plain)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func row(_ item: FilamentRunway) -> some View {
        HStack(spacing: 12) {
            FilamentSwatch(colors: item.colors, size: 24)
            Text(item.title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 8)
            Text(String(format: "%.0f g", item.remainingGrams)).font(.subheadline).foregroundStyle(.secondary)
            if let days = item.daysOfStock {
                Text(runwayChipText(days))
                    .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(.red)
            }
        }
    }

    private func runwayChipText(_ days: Double) -> String {
        days < 14 ? "~\(Int(days.rounded())) d" : "~\(Int((days / 7).rounded())) wk"
    }
}

/// Colours — top colour swatches from the active spool inventory; display only.
struct ColorsCard: View {
    let stats: [ColorStat]
    let distinctCount: Int
    private let maxSwatches = 8

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DashboardCardTitle(title: "Colours", info: DashboardInfo.colours)
                    Spacer()
                    Text("\(distinctCount) in stock").font(.subheadline).foregroundStyle(.secondary)
                }
                if stats.isEmpty {
                    Text("No colours yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 7) {
                        ForEach(stats.prefix(maxSwatches)) { stat in
                            Circle()
                                .fill(Color(hex: stat.hex) ?? .swatchFallback)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.swatchBorder, lineWidth: 1))
                        }
                        if stats.count > maxSwatches {
                            Text("+\(stats.count - maxSwatches)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// Total Value — sum of purchase prices across active spools.
struct TotalValueCard: View {
    let value: String
    /// `DashboardInfo.totalValue(_:)` — the currency line depends on the backend.
    let info: [String]
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                DashboardCardTitle(title: "Total value", info: info)
                Text(value).font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
    }
}

/// Locations — how many locations exist and how many spools sit outside all
/// of them; the whole card is a `NavigationLink` into Manage Locations.
struct LocationsCard: View {
    let summary: LocationSummary

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Label("Locations", systemImage: "mappin.and.ellipse")
                    .font(.headline)

                Text("\(summary.locationCount) \(summary.locationCount == 1 ? "location" : "locations")")
                    .font(.title2.weight(.semibold))

                Text(summary.unassignedSpoolCount == 0
                     ? "Every spool has a location"
                     : "\(summary.unassignedSpoolCount) \(summary.unassignedSpoolCount == 1 ? "spool has" : "spools have") no location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Material Statistics — per-material spool count and remaining weight; each row
/// drills into spools of that material.
struct MaterialStatisticsCard: View {
    let stats: [MaterialStat]

    private let spoolsColumn: CGFloat = 70
    private let remainingColumn: CGFloat = 100

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 8) {
                DashboardCardTitle(title: "Material Statistics", info: DashboardInfo.materialStatistics)
                HStack {
                    Text("MATERIAL").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SPOOLS").frame(width: spoolsColumn, alignment: .trailing)
                    Text("REMAINING").frame(width: remainingColumn, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Divider()
                if stats.isEmpty {
                    Text("No spools yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(stats) { stat in
                        NavigationLink(value: SpoolFilter.material(stat.material)) {
                            row(stat)
                        }
                        .buttonStyle(.plain)
                        if stat.id != stats.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func row(_ stat: MaterialStat) -> some View {
        HStack {
            Text(stat.material).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(stat.spoolCount)").frame(width: spoolsColumn, alignment: .trailing)
            Text(String(format: "%.1f kg", stat.remainingKilograms))
                .frame(width: remainingColumn, alignment: .trailing)
        }
        .font(.body)
    }
}
