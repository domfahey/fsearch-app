import Testing

@testable import FSearchKit

@Suite struct PanelRowsTests {
    @Test func fallbackRowsFollowFilesInNamesMode() {
        #expect(PanelRows.count(files: 3, query: "abc", mode: .names) == 5)
        #expect(PanelRows.row(at: 2, files: 3, query: "abc", mode: .names) == .result(2))
        #expect(PanelRows.row(at: 3, files: 3, query: "abc", mode: .names) == .searchInside)
        #expect(PanelRows.row(at: 4, files: 3, query: "abc", mode: .names) == .findDefinitions)
        #expect(PanelRows.row(at: 5, files: 3, query: "abc", mode: .names) == nil)
    }

    @Test func noFallbackRowsWhenEmptyOrNotNames() {
        #expect(PanelRows.count(files: 3, query: "", mode: .names) == 3)
        #expect(PanelRows.count(files: 3, query: "abc", mode: .content) == 3)
        #expect(PanelRows.row(at: 3, files: 3, query: "abc", mode: .symbols) == nil)
        #expect(PanelRows.row(at: -1, files: 3, query: "abc", mode: .names) == nil)
    }

    @Test func fallbacksAreReachableWithNoFiles() {
        #expect(PanelRows.row(at: 0, files: 0, query: "abc", mode: .names) == .searchInside)
    }

    @Test func fallbackModes() {
        #expect(PanelRow.searchInside.mode == .content)
        #expect(PanelRow.findDefinitions.mode == .symbols)
        #expect(PanelRow.result(0).mode == nil)
    }
}

@Suite struct PanelRowsEdgeTests {
    @Test func whitespaceOnlyQueryHasNoFallbacks() {
        #expect(PanelRows.count(files: 0, query: "   ", mode: .names) == 0)
    }
    @Test func cheatSheetHasNoFallbacks() {
        #expect(PanelRows.count(files: 0, query: "?", mode: .names) == 0)
    }
    @Test func contentKeyQueryHasNoFallbacks() {
        #expect(PanelRows.count(files: 2, query: "grep:needle", mode: .names) == 2)
    }
}

@Suite struct PanelRowsValueTests {
    @Test(arguments: ["abc", "", "   ", "?", "grep:x", "foo ext:rs"])
    func valueMatchesStaticForwarders(query: String) {
        for mode in [SearchMode.names, .content, .symbols] {
            for files in [0, 3] {
                let rows = PanelRows(files: files, query: query, mode: mode)
                #expect(rows.hasFallbacks == PanelRows.hasFallbacks(query: query, mode: mode))
                #expect(rows.count == PanelRows.count(files: files, query: query, mode: mode))
                for i in -1...(rows.count + 1) {
                    #expect(rows.row(at: i) == PanelRows.row(at: i, files: files, query: query, mode: mode))
                }
            }
        }
    }
}
