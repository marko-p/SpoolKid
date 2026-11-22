import Testing
import Foundation
@testable import SpoolKid

struct SpoolListGroupingTests {
    // The owner's real Spoolman data.
    private var azure: Vendor { Vendor(id: 1, name: "AzureFilm") }
    private var prusa: Vendor { Vendor(id: 2, name: "Prusament") }
    private var velvet: Filament { Filament(id: 12, name: "Silk Dual Color Velvet Bloom", material: "PLA", vendor: azure) }
    private var white: Filament { Filament(id: 7, name: "Original WHITE", material: "PETG", vendor: azure) }
    private var tiger: Filament { Filament(id: 4, name: "Original TIGER ORANGE", material: "PETG", vendor: azure) }
    private var asa: Filament { Filament(id: 10, name: "ASA Signal White", material: "ASA", vendor: prusa) }
    private var galaxy: Filament { Filament(id: 2, name: "Galaxy Black", material: "PETG", vendor: prusa) }
    private var matte: Filament { Filament(id: 3, name: "Matte Grey", material: "PLA", vendor: azure) }
    private let touched = Date(timeIntervalSince1970: 1_800_000_000)

    /// The five spools in the caller's order.
    private var inventory: [Spool] {
        [
            spool(7, velvet, remaining: 992.6, initial: 1000, used: 7.4, lastUsed: touched, location: "AMS"),
            spool(4, white, remaining: 244.2, initial: 1000, used: 755.8, lastUsed: touched, location: "Dry box"),
            spool(2, tiger, remaining: 1000, initial: 1000, used: 0),
            spool(8, tiger, remaining: 1000, initial: 1000, used: 0),
            spool(5, asa, remaining: 818, initial: 818, used: 0, location: "Shelf"),
        ]
    }

    private func spool(_ id: Int, _ filament: Filament, remaining: Double, initial: Double, used: Double,
                       lastUsed: Date? = nil, location: String? = nil, archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: filament, lastUsed: lastUsed, remainingWeight: remaining,
              initialWeight: initial, usedWeight: used, location: location, archived: archived,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    private func grouped(_ rows: [Spool], totals: [Spool]? = nil, mode: SpoolGrouping, folds: Bool = true,
                         searching: Bool = false) -> [SpoolGroup] {
        SpoolListGrouping.groups(rows: rows, totalsFrom: totals ?? rows, mode: mode, foldsUnused: folds,
                                 isSearching: searching)
    }

    private func group(_ id: String, in groups: [SpoolGroup]) -> SpoolGroup? {
        groups.first { $0.id == id }
    }

    private func folds(in group: SpoolGroup) -> [SpoolFold] {
        var result: [SpoolFold] = []
        for entry in group.entries {
            if case .fold(let fold) = entry { result.append(fold) }
        }
        return result
    }

    private func describe(_ entry: SpoolListEntry) -> String {
        switch entry {
        case .spool(let spool): "\(spool.id)"
        case .fold(let fold): "fold[\(fold.spools.map { "\($0.id)" }.joined(separator: ","))]"
        }
    }

    @Test func filamentModeGroupsInRowOrder() {
        let groups = grouped(inventory, mode: .filament)
        #expect(groups.map(\.id) == ["filament:12", "filament:7", "filament:4", "filament:10"])
        #expect(groups.first?.title == "Silk Dual Color Velvet Bloom")
    }

    @Test func identicalUnusedSpoolsFold() throws {
        let tigerGroup = try #require(group("filament:4", in: grouped(inventory, mode: .filament)))
        #expect(tigerGroup.entries.map(describe) == ["fold[2,8]"])
        #expect(folds(in: tigerGroup).first?.basis == 1000)
        #expect(tigerGroup.spoolIDs == [2, 8])
    }

    @Test func noFoldsWhenTurnedOff() throws {
        let tigerGroup = try #require(group("filament:4", in: grouped(inventory, mode: .filament, folds: false)))
        #expect(tigerGroup.entries.map(describe) == ["2", "8"])
    }

    @Test func headerTotals() throws {
        let tigerGroup = try #require(group("filament:4", in: grouped(inventory, mode: .filament)))
        #expect(tigerGroup.spoolCount == 2)
        #expect(tigerGroup.remaining == 2000)
        let azureGroup = try #require(group("manufacturer:1", in: grouped(inventory, mode: .manufacturer)))
        #expect(azureGroup.spoolCount == 4)
        #expect(abs(try #require(azureGroup.remaining) - 3236.8) < 0.001)
    }

    @Test func manufacturerModeOrder() {
        let groups = grouped(inventory, mode: .manufacturer)
        #expect(groups.map(\.id) == ["manufacturer:1", "manufacturer:2"])
        #expect(groups.first?.vendor?.id == 1)
    }

    @Test func materialModeOrder() {
        #expect(grouped(inventory, mode: .material).map(\.id) == ["material:PLA", "material:PETG", "material:ASA"])
    }

    @Test func locationNoneGroupIsLast() throws {
        let groups = grouped(inventory, mode: .location)
        #expect(groups.map(\.id) == ["location:AMS", "location:Dry box", "location:Shelf", "location:"])
        let last = try #require(groups.last)
        #expect(last.title == "No location")
        #expect(last.isNoneGroup)
    }

    @Test func whitespaceLocationIsNoLocation() {
        let rows = [
            spool(2, tiger, remaining: 1000, initial: 1000, used: 0, location: "  "),
            spool(7, velvet, remaining: 992.6, initial: 1000, used: 7.4, lastUsed: touched, location: "AMS"),
        ]
        #expect(grouped(rows, mode: .location).map(\.id) == ["location:AMS", "location:"])
    }

    // A stray space never splits a shelf in two, in the group key, the title or the
    // fold key.
    @Test func locationKeyAndTitleAreTrimmed() throws {
        let rows = [
            spool(7, velvet, remaining: 992.6, initial: 1000, used: 7.4, lastUsed: touched, location: "AMS"),
            spool(4, white, remaining: 244.2, initial: 1000, used: 755.8, lastUsed: touched, location: "AMS "),
            spool(5, asa, remaining: 818, initial: 818, used: 0, location: " Shelf"),
        ]
        let groups = grouped(rows, mode: .location)
        #expect(groups.map(\.id) == ["location:AMS", "location:Shelf"])
        let ams = try #require(groups.first)
        #expect(ams.title == "AMS")
        #expect(ams.location == "AMS")
        #expect(ams.entries.map(describe) == ["7", "4"])
        #expect(ams.spoolCount == 2)
        #expect(groups.last?.title == "Shelf")
    }

    @Test func missingVendorIsLastNoManufacturer() throws {
        let loose = Filament(id: 20, name: "Loose", material: "PLA")
        let rows = [spool(9, loose, remaining: 1000, initial: 1000, used: 0)] + inventory
        let last = try #require(grouped(rows, mode: .manufacturer).last)
        #expect(last.id == "manufacturer:")
        #expect(last.title == "No manufacturer")
        #expect(last.isNoneGroup)
    }

    @Test func blankMaterialIsUnknownAndLast() throws {
        let mystery = Filament(id: 21, name: "Mystery", material: " ", vendor: azure)
        let rows = [spool(9, mystery, remaining: 500, initial: 1000, used: 500)] + inventory
        let last = try #require(grouped(rows, mode: .material).last)
        #expect(last.id == "material:Unknown")
        #expect(last.isNoneGroup)
    }

    @Test func totalsIgnoreTheSearch() throws {
        let tigerOnly = inventory.filter { $0.id == 2 }
        let groups = grouped(tigerOnly, totals: inventory, mode: .filament)
        #expect(groups.map(\.id) == ["filament:4"])
        let tigerGroup = try #require(groups.first)
        #expect(tigerGroup.spoolCount == 2)
        #expect(tigerGroup.remaining == 2000)
    }

    @Test func archivedNeverFoldsOrCounts() throws {
        let archivedTiger = spool(9, tiger, remaining: 1000, initial: 1000, used: 0, archived: true)
        let rows = inventory + [archivedTiger]
        let tigerGroup = try #require(group("filament:4", in: grouped(rows, mode: .filament)))
        #expect(tigerGroup.entries.map(describe) == ["fold[2,8]", "9"])
        #expect(tigerGroup.spoolCount == 2)
    }

    @Test func archivedOnlyGroupCountsZero() throws {
        let archivedAsa = spool(11, asa, remaining: 300, initial: 1000, used: 700, archived: true)
        let groups = grouped([archivedAsa], mode: .filament)
        #expect(groups.count == 1)
        let only = try #require(groups.first)
        #expect(only.spoolCount == 0)
        #expect(only.remaining == nil)
    }

    // An over-drawn spool (a negative reading) must not cancel out the grams its
    // neighbours hold.
    @Test func negativeRemainingCountsAsZeroInTotals() throws {
        let rows = [
            spool(2, tiger, remaining: 500, initial: 1000, used: 500),
            spool(8, tiger, remaining: -120, initial: 1000, used: 1120),
        ]
        let tigerGroup = try #require(group("filament:4", in: grouped(rows, mode: .filament)))
        #expect(tigerGroup.spoolCount == 2)
        #expect(tigerGroup.remaining == 500)
    }

    @Test func unknownWeightsTotalNil() throws {
        let unweighed = [4, 5].map { id in
            Spool(id: id, filament: tiger, lastUsed: nil, remainingWeight: nil, initialWeight: nil,
                  usedWeight: nil, location: nil, archived: nil, statusId: nil, externalId: nil, purchaseDate: nil)
        }
        let tigerGroup = try #require(group("filament:4", in: grouped(unweighed, mode: .filament)))
        #expect(tigerGroup.spoolCount == 2)
        #expect(tigerGroup.remaining == nil)
    }

    @Test func differentShelvesDoNotFold() throws {
        let rows = [
            spool(2, tiger, remaining: 1000, initial: 1000, used: 0, location: "Shelf"),
            spool(8, tiger, remaining: 1000, initial: 1000, used: 0),
        ]
        let tigerGroup = try #require(group("filament:4", in: grouped(rows, mode: .filament)))
        #expect(tigerGroup.entries.map(describe) == ["2", "8"])
    }

    @Test func nilBasisSpoolsNeverFold() throws {
        let bare = Filament(id: 30, name: "Bare", material: "PLA")
        let rows = [
            Spool(id: 40, filament: bare, lastUsed: nil, remainingWeight: 300, initialWeight: nil,
                  usedWeight: nil, location: "Shelf", archived: nil, statusId: nil, externalId: nil, purchaseDate: nil),
            Spool(id: 41, filament: bare, lastUsed: nil, remainingWeight: 300, initialWeight: nil,
                  usedWeight: nil, location: "Shelf", archived: nil, statusId: nil, externalId: nil, purchaseDate: nil),
        ]
        let bareGroup = try #require(group("filament:30", in: grouped(rows, mode: .filament)))
        #expect(bareGroup.entries.map(describe) == ["40", "41"])
        #expect(folds(in: bareGroup).isEmpty)
    }

    @Test func differentRemainingDoesNotFold() throws {
        let rows = [
            spool(2, tiger, remaining: 1000, initial: 1000, used: 0),
            spool(8, tiger, remaining: 1200, initial: 1000, used: 0),
        ]
        let tigerGroup = try #require(group("filament:4", in: grouped(rows, mode: .filament)))
        #expect(tigerGroup.entries.map(describe) == ["2", "8"])
    }

    @Test func singleUnusedSpoolIsARow() throws {
        let asaGroup = try #require(group("filament:10", in: grouped(inventory, mode: .filament)))
        #expect(asaGroup.entries.map(describe) == ["5"])
    }

    @Test func noneModeIsOneGroup() throws {
        let groups = grouped(inventory, mode: .none)
        #expect(groups.map(\.id) == ["all"])
        let only = try #require(groups.first)
        #expect(only.entries.map(describe) == ["7", "4", "fold[2,8]", "5"])
    }

    // I3: "search forces groups open" is the service's rule, so both screens share it.
    @Test func searchForcesEveryGroupOpen() {
        let browsing = grouped(inventory, mode: .filament)
        #expect(browsing.allSatisfy { !$0.forcedOpen })

        let searching = grouped(inventory, mode: .filament, searching: true)
        #expect(!searching.isEmpty)
        #expect(searching.allSatisfy { $0.forcedOpen })

        for mode in SpoolGrouping.allCases {
            #expect(grouped(inventory, mode: mode, searching: true).allSatisfy { $0.forcedOpen })
            #expect(grouped(inventory, mode: mode).allSatisfy { !$0.forcedOpen })
        }
    }

    // O24: identical unused spools fold only under a filament, so `foldsUnused` is
    // true for the filament drill-down and for Filament grouping, and nowhere else.
    @Test func layoutTable() {
        for grouping in SpoolGrouping.allCases {
            #expect(SpoolListGrouping.layout(grouping: grouping, isFilamentDrillDown: true)
                    == SpoolListLayout(mode: .none, showsHeaders: false, rowStyle: .underFilament))
            #expect(SpoolListGrouping.layout(grouping: grouping, isFilamentDrillDown: true).foldsUnused)
        }
        #expect(SpoolListGrouping.layout(grouping: .filament, isFilamentDrillDown: false)
                == SpoolListLayout(mode: .filament, showsHeaders: true, rowStyle: .underFilament))
        #expect(SpoolListGrouping.layout(grouping: .filament, isFilamentDrillDown: false).foldsUnused)
        #expect(SpoolListGrouping.layout(grouping: .manufacturer, isFilamentDrillDown: false)
                == SpoolListLayout(mode: .manufacturer, showsHeaders: true, rowStyle: .withFilamentNameOnly))
        #expect(!SpoolListGrouping.layout(grouping: .manufacturer, isFilamentDrillDown: false).foldsUnused)
        #expect(SpoolListGrouping.layout(grouping: .material, isFilamentDrillDown: false)
                == SpoolListLayout(mode: .material, showsHeaders: true, rowStyle: .withFilamentNoMaterial))
        #expect(!SpoolListGrouping.layout(grouping: .material, isFilamentDrillDown: false).foldsUnused)
        #expect(SpoolListGrouping.layout(grouping: .location, isFilamentDrillDown: false)
                == SpoolListLayout(mode: .location, showsHeaders: true, rowStyle: .withFilament))
        #expect(!SpoolListGrouping.layout(grouping: .location, isFilamentDrillDown: false).foldsUnused)
        #expect(SpoolListGrouping.layout(grouping: .none, isFilamentDrillDown: false)
                == SpoolListLayout(mode: .none, showsHeaders: false, rowStyle: .withFilament))
        #expect(!SpoolListGrouping.layout(grouping: .none, isFilamentDrillDown: false).foldsUnused)
    }

    // O25: only rows under a filament are compact; every other list keeps the
    // List's own row height.
    @Test func compactRowsOnlyUnderAFilament() {
        for grouping in SpoolGrouping.allCases {
            #expect(SpoolListGrouping.layout(grouping: grouping, isFilamentDrillDown: true).usesCompactRows)
            #expect(SpoolListGrouping.layout(grouping: grouping, isFilamentDrillDown: false).usesCompactRows
                    == (grouping == .filament))
        }
    }

    @Test func toolbarSymbolIsThePlainGroupIconForNone() {
        #expect(SpoolGrouping.none.toolbarSymbol == "rectangle.3.group")
        #expect(SpoolGrouping.none.isHighlightedInToolbar == false)
    }

    @Test func toolbarSymbolIsTheCategoryIconWhileGrouping() {
        #expect(SpoolGrouping.filament.toolbarSymbol == "scribble")
        #expect(SpoolGrouping.manufacturer.toolbarSymbol == "building.2")
        #expect(SpoolGrouping.material.toolbarSymbol == "cube")
        #expect(SpoolGrouping.location.toolbarSymbol == "mappin.and.ellipse")
        for grouping in SpoolGrouping.allCases where grouping != .none {
            #expect(grouping.isHighlightedInToolbar)
            #expect(grouping.toolbarSymbol == grouping.systemImage)
        }
    }

    @Test func titleMenuNamesWhatTheListIsMadeOf() {
        #expect(SpoolGrouping.allCases.map(\.titleMenuLabel)
                == ["Filaments", "Manufacturers", "Materials", "Colors", "Locations", "All Spools"])
    }

    // MARK: - Groups without spools

    private var velvetSpool: Spool { spool(7, velvet, remaining: 992.6, initial: 1000, used: 7.4) }

    private func spoolless(_ filaments: [Filament], vendors: [Vendor] = [], visible: [Spool],
                           mode: SpoolGrouping = .filament, filtersActive: Bool = false,
                           search: String = "") -> [SpoolGroup] {
        SpoolListGrouping.groupsWithoutSpools(filaments: filaments, vendors: vendors, visibleSpools: visible,
                                              mode: mode, filtersActive: filtersActive, searchText: search)
    }

    @Test func spoollessGroupsOnlyUnderFilamentOrManufacturerGrouping() {
        #expect(spoolless([velvet, galaxy], visible: [velvetSpool]).map(\.id) == ["filament:2"])
        for mode in [SpoolGrouping.material, .location, .none] {
            #expect(spoolless([velvet, galaxy], vendors: [azure, prusa], visible: [velvetSpool], mode: mode).isEmpty)
        }
    }

    // velvet is AzureFilm's: only Prusament has no visible spool.
    @Test func spoollessManufacturersAreTheOnesNoVisibleSpoolIsMadeBy() {
        let groups = spoolless([velvet, galaxy], vendors: [azure, prusa], visible: [velvetSpool], mode: .manufacturer)
        #expect(groups.map(\.id) == ["manufacturer:2"])
        #expect(groups.first?.vendor?.name == "Prusament")
        #expect(groups.first?.filament == nil)
        #expect(groups.first?.entries.isEmpty == true)
    }

    @Test func spoollessManufacturersMatchSearchByNameAndHideWhileFiltering() {
        #expect(spoolless([], vendors: [azure, prusa], visible: [], mode: .manufacturer, search: "prus")
                .map(\.id) == ["manufacturer:2"])
        #expect(spoolless([], vendors: [azure, prusa], visible: [], mode: .manufacturer, filtersActive: true).isEmpty)
    }

    @Test func spoollessManufacturersAreOrderedByName() {
        let vendors = [Vendor(id: 5, name: "b"), Vendor(id: 6, name: "A"), Vendor(id: 7, name: "c")]
        #expect(spoolless([], vendors: vendors, visible: [], mode: .manufacturer).map(\.title) == ["A", "b", "c"])
    }

    @Test func spoollessFilamentsHideWhileFiltering() {
        #expect(spoolless([velvet, galaxy], visible: [velvetSpool], filtersActive: true).isEmpty)
    }

    // The caller passes the spools after archived-exclusion: a filament whose only
    // spool is archived shows only while archived spools are shown.
    @Test func spoollessFilamentsRespectShowArchived() {
        let archivedMatte = spool(9, matte, remaining: 500, initial: 1000, used: 500, archived: true)
        #expect(spoolless([velvet, matte], visible: [velvetSpool]).map(\.id).contains("filament:3"))
        #expect(!spoolless([velvet, matte], visible: [velvetSpool, archivedMatte]).map(\.id).contains("filament:3"))
    }

    @Test func spoollessFilamentsMatchSearchLikeHeaders() {
        // galaxy: name "Galaxy Black", vendor "Prusament", material "PETG"
        for query in ["galaxy", "prusa", "petg"] {
            #expect(spoolless([velvet, galaxy], visible: [velvetSpool], search: query).map(\.id) == ["filament:2"])
        }
        #expect(spoolless([velvet, galaxy], visible: [velvetSpool], search: "zzz").isEmpty)
    }

    @Test func spoollessFilamentsAreOrderedByTitle() {
        let lowerB = Filament(id: 31, name: "b", material: "PLA", vendor: azure)
        let upperA = Filament(id: 32, name: "A", material: "PLA", vendor: azure)
        let lowerC = Filament(id: 33, name: "c", material: "PLA", vendor: azure)
        #expect(spoolless([lowerB, upperA, lowerC], visible: []).map(\.title) == ["A", "b", "c"])
    }

    // MARK: - Recently Added

    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    private func added(_ id: Int, _ filament: Filament, hoursAgo: Double?, archived: Bool? = nil) -> Spool {
        Spool(id: id, filament: filament,
              registered: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
              remainingWeight: 1000, initialWeight: 1000, usedWeight: 0, archived: archived,
              statusId: nil, externalId: nil, purchaseDate: nil)
    }

    @Test func recentlyAddedTakesSpoolsAddedWithinTheLastDay() {
        let rows = [added(1, white, hoursAgo: 30), added(2, white, hoursAgo: 1),
                    added(3, tiger, hoursAgo: nil), added(4, asa, hoursAgo: 23.9)]
        let split = SpoolListGrouping.splittingRecentlyAdded(rows, now: now)
        #expect(split.recent.map(\.id) == [2, 4])
        #expect(split.rest.map(\.id) == [1, 3])
    }

    @Test func recentlyAddedListsTheNewestFirst() {
        let rows = [added(1, white, hoursAgo: 5), added(2, white, hoursAgo: 1), added(3, asa, hoursAgo: 12)]
        #expect(SpoolListGrouping.splittingRecentlyAdded(rows, now: now).recent.map(\.id) == [2, 1, 3])
    }

    @Test func archivedSpoolsAreNeverRecentlyAdded() {
        let rows = [added(1, white, hoursAgo: 1, archived: true)]
        let split = SpoolListGrouping.splittingRecentlyAdded(rows, now: now)
        #expect(split.recent.isEmpty)
        #expect(split.rest.map(\.id) == [1])
    }

    /// A server clock a little ahead of the phone still means "just added".
    @Test func aSpoolDatedAheadOfTheClockIsRecentlyAdded() {
        let rows = [added(1, white, hoursAgo: -0.1)]
        #expect(SpoolListGrouping.splittingRecentlyAdded(rows, now: now).recent.map(\.id) == [1])
    }

    /// Same headers, rows and folds as the rest of the list (owner 2026-11-10),
    /// under ids of their own.
    @Test func recentlyAddedGroupsLikeTheRestOfTheList() throws {
        let recent = [added(2, tiger, hoursAgo: 1), added(8, tiger, hoursAgo: 2), added(5, asa, hoursAgo: 3)]
        let groups = SpoolListGrouping.recentlyAddedGroups(recent, mode: .filament, foldsUnused: true)
        #expect(groups.map(\.id) == ["recent:filament:4", "recent:filament:10"])
        let tigerGroup = try #require(groups.first)
        #expect(tigerGroup.filament?.id == 4)
        #expect(tigerGroup.entries.map(describe) == ["fold[2,8]"])
        #expect(tigerGroup.spoolCount == 2)
        #expect(tigerGroup.remaining == 2000)
    }

    /// A filament in both lists keeps separate ids, so collapsing or expanding
    /// one never moves the other.
    @Test func recentlyAddedIDsNeverClashWithTheRestOfTheList() {
        let recent = [added(2, tiger, hoursAgo: 1), added(8, tiger, hoursAgo: 2)]
        let rest = [added(3, tiger, hoursAgo: 48), added(9, tiger, hoursAgo: 49)]
        let recentGroups = SpoolListGrouping.recentlyAddedGroups(recent, mode: .filament, foldsUnused: true)
        let restGroups = grouped(rest, mode: .filament)
        let recentIDs = Set(recentGroups.map(\.id) + recentGroups.flatMap { folds(in: $0).map(\.id) })
        let restIDs = Set(restGroups.map(\.id) + restGroups.flatMap { folds(in: $0).map(\.id) })
        #expect(recentIDs.isDisjoint(with: restIDs))
        #expect(recentIDs.count == 2)
    }

    @Test func noRecentlyAddedGroupsWithoutRecentSpools() {
        #expect(SpoolListGrouping.recentlyAddedGroups([], mode: .filament, foldsUnused: true).isEmpty)
    }

    /// The spool moves out of its filament's rows, but the filament header still counts it.
    @Test func aRecentSpoolStillCountsInItsNormalGroupsTotals() throws {
        let all = [added(1, white, hoursAgo: 48), added(2, white, hoursAgo: 1)]
        let split = SpoolListGrouping.splittingRecentlyAdded(all, now: now)
        let groups = grouped(split.rest, totals: all, mode: .filament, folds: false)
        let whiteGroup = try #require(group("filament:7", in: groups))
        #expect(whiteGroup.entries.map(describe) == ["1"])
        #expect(whiteGroup.spoolCount == 2)
    }

    @Test func recentlyAddedShowsOnlyOnTheUnsearchedUnfilteredLibraryList() {
        #expect(SpoolListGrouping.offersRecentlyAdded(isLibraryList: true, isSearching: false, filtersActive: false))
        #expect(!SpoolListGrouping.offersRecentlyAdded(isLibraryList: false, isSearching: false, filtersActive: false))
        #expect(!SpoolListGrouping.offersRecentlyAdded(isLibraryList: true, isSearching: true, filtersActive: false))
        #expect(!SpoolListGrouping.offersRecentlyAdded(isLibraryList: true, isSearching: false, filtersActive: true))
    }

    // MARK: - Color

    @Test func colorGroupsFollowTheSpectrumWithNoColorLast() {
        func colored(_ id: Int, _ hex: String?) -> Spool {
            spool(id, Filament(id: id * 10, name: "F\(id)", material: "PLA", colorHex: hex),
                  remaining: 500, initial: 1000, used: 500)
        }
        let rows = [colored(1, "2196F3"), colored(2, nil), colored(3, "FF0000"), colored(4, "1E88E5")]
        let groups = grouped(rows, mode: .color, folds: false)
        #expect(groups.map(\.title) == ["Red", "Blue", "No color"])
        #expect(groups.first { $0.title == "Blue" }?.spoolCount == 2)
        #expect(groups.first?.colorFamily == .red)
        #expect(groups.last?.isNoneGroup == true)
    }

    @Test func colorGroupingShowsHeadersAndNamesEachFilament() {
        let layout = SpoolListGrouping.layout(grouping: .color, isFilamentDrillDown: false)
        #expect(layout.showsHeaders)
        #expect(layout.rowStyle == .withFilament)
    }
}

