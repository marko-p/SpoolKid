import Foundation

protocol SortOption: CaseIterable, Identifiable {
    var label: String { get }
    var systemImage: String { get }
    /// False for an order `ascending` does not affect, so a menu never shows
    /// a direction the list will not follow.
    var isDirectional: Bool { get }
}

extension SortOption {
    var isDirectional: Bool { true }
}

nonisolated enum SpoolSortOption: String, SortOption, CaseIterable, Identifiable {
    case name
    case vendor
    case material
    case remainingWeight
    case lastUsed
    case recent
    case location
    case id

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .vendor: return "Manufacturer"
        case .material: return "Material"
        case .remainingWeight: return "Remaining Weight"
        case .lastUsed: return "Last Used"
        case .recent: return "Recent"
        case .location: return "Location"
        case .id: return "Spool ID"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .vendor: return "building"
        case .material: return "cube"
        case .remainingWeight: return "scalemass"
        case .lastUsed: return "clock"
        case .recent: return "clock.arrow.circlepath"
        case .location: return "mappin"
        case .id: return "number"
        }
    }

    func areInIncreasingOrder(_ a: Spool, _ b: Spool) -> Bool {
        switch self {
        case .name:
            return (a.filament.name ?? "").localizedCaseInsensitiveCompare(b.filament.name ?? "") == .orderedAscending
        case .vendor:
            return (a.filament.vendor?.name ?? "").localizedCaseInsensitiveCompare(b.filament.vendor?.name ?? "") == .orderedAscending
        case .material:
            return (a.filament.material ?? "").localizedCaseInsensitiveCompare(b.filament.material ?? "") == .orderedAscending
        case .remainingWeight:
            return (a.remainingWeight ?? 0) < (b.remainingWeight ?? 0)
        case .lastUsed:
            // Never-used spools all read `.distantPast`, so they tie. Break the
            // tie by registration (the spool added later is the more recent one),
            // then by id, so the order stays total and the descending flip is a
            // valid ordering. Spoolman and FilaMan record no edit time (the Library
            // has `updatedAt`), so "Modified" is not offered, for parity.
            let x = a.lastUsed ?? .distantPast
            let y = b.lastUsed ?? .distantPast
            if x != y { return x < y }
            let rx = a.registered ?? .distantPast
            let ry = b.registered ?? .distantPast
            if rx != ry { return rx < ry }
            return a.id < b.id
        case .recent:
            // Oldest first, so the descending flip lists the newest first. The
            // rule is `DashboardStatsService.isMoreRecent`: last used, else registered.
            // A Library spool created before it recorded its added date has
            // neither until it is weighed, so it falls back to the id: newest
            // id first when descending.
            return DashboardStatsService.isMoreRecent(b, a)
        case .location:
            return (a.location ?? "").localizedCaseInsensitiveCompare(b.location ?? "") == .orderedAscending
        case .id:
            return a.id < b.id
        }
    }
}
