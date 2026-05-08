import Testing
@testable import SpoolKid

struct AppConfigOpenPrintTagGroupingTests {
    @Test func materialTagGroupsMatchUXSpec() {
        let expected: [(title: String, ids: [Int])] = [
            ("Biological", [0, 1, 2, 3, 61, 62, 63]),
            ("Physical", [4, 5, 6, 7, 8, 9, 71, 67]),
            ("Electrical", [10, 11, 70]),
            ("Chemical", [12, 13, 14, 15, 64]),
            ("Visual & Color", [16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 65]),
            ("Carbon", [30, 31, 32, 72]),
            ("Glass & Kevlar", [33, 34, 35, 68]),
            ("Minerals", [36, 37]),
            ("Organic Materials", [38, 39, 40, 41, 42, 43, 66]),
            ("Ceramic", [44, 45]),
            ("Metals", [46, 47, 48, 49, 50, 51, 52, 53, 54]),
            ("Imitation", [55, 56, 57, 58]),
            ("Other", [59, 60, 69])
        ]

        #expect(AppConfig.openPrintTagMaterialTagGroups.count == expected.count)
        for (index, group) in AppConfig.openPrintTagMaterialTagGroups.enumerated() {
            #expect(group.title == expected[index].title)
            #expect(group.ids == expected[index].ids)
        }
    }

    @Test func certificationsAreUngrouped() {
        #expect(AppConfig.openPrintTagCertificationGroups.isEmpty)
    }
}
