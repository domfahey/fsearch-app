import Foundation
import Synchronization
import Testing

@testable import FSearchKit

@Suite struct SearchWindowQueryTests {
    @Test func filterChipsNormalizeQuoteAndExposePresets() {
        #expect(!SearchFilterChip.typePresets.isEmpty)
        #expect(!SearchFilterChip.kindPresets.isEmpty)
        #expect(!SearchFilterChip.sizePresets.isEmpty)
        #expect(!SearchFilterChip.modifiedPresets.isEmpty)
        #expect(!SearchFilterChip.folderPresets.isEmpty)

        let spaced = SearchFilterChip(kind: .folder, value: "~/My Projects")
        #expect(spaced.id == "in:~/My Projects")
        #expect(spaced.title == "in:~/My Projects")
        #expect(spaced.token == "in:\"~/My Projects\"")

        let exts = SearchFilterChip.extensionChip(" .Swift, MD , .rs, swift ")
        #expect(exts?.value == "md,rs,swift")
        #expect(exts?.token == "ext:md,rs,swift")
        #expect(SearchFilterChip.extensionChip(" , . ") == nil)
        // Folder presets use "in:" prefix so "in:Documents" never collides with type:doc's "Documents".
        #expect(SearchFilterChip.folderPresets.allSatisfy { $0.title.hasPrefix("in:") })

        let folder = SearchFilterChip.folderChip("/tmp/My Folder")
        #expect(folder?.kind == .folder)
        #expect(folder?.title == "in:My Folder")
        #expect(folder?.token == "in:\"/tmp/My Folder\"")
        #expect(SearchFilterChip.folderChip("/")?.title == "/")
        #expect(SearchFilterChip.folderChip("   ") == nil)
    }

    @Test func compilesFastPathChipsAndLimits() {
        #expect(SearchWindowQuery.compile(rawQuery: "   ", mode: .names) == .empty)

        let plain = SearchWindowQuery.compile(rawQuery: "report", mode: .names)
        #expect(plain == .names(query: "report", limit: 1000, clientFilter: nil))

        let withChips = SearchWindowQuery.compile(
            rawQuery: "report", mode: .names,
            chips: [SearchFilterChip(kind: .ext, value: "pdf"), SearchFilterChip(kind: .size, value: ">1mb")])
        #expect(withChips == .names(query: "report ext:pdf size:>1mb", limit: 1000, clientFilter: nil))

        let chipOnly = SearchWindowQuery.compile(
            rawQuery: "", mode: .names, chips: [SearchFilterChip(kind: .type, value: "code")])
        #expect(chipOnly == .names(query: "type:code", limit: 1000, clientFilter: nil))

        let explicitLimit = SearchWindowQuery.compile(rawQuery: "report limit:250", mode: .names)
        #expect(explicitLimit == .names(query: "report limit:250", limit: 250, clientFilter: nil))

        let cappedLimit = SearchWindowQuery.compile(rawQuery: "report limit:5000", mode: .names)
        #expect(cappedLimit == .names(query: "report limit:5000", limit: 1000, clientFilter: nil))
    }

    @Test func compilesMatchTogglesForSingleTermMultiTermRegexAndPath() {
        // Lone quotes with match toggles active must not trap on an empty term list.
        #expect(SearchWindowQuery.compile(rawQuery: "\"", mode: .names, options: SearchMatchOptions(matchCase: true)) == .empty)
        #expect(SearchWindowQuery.compile(rawQuery: "\"\"", mode: .names, options: SearchMatchOptions(wholeWord: true)) == .empty)
        #expect(
            SearchWindowQuery.compile(rawQuery: "ext:swift \"\"", mode: .names, options: SearchMatchOptions(searchInPath: true))
                == .names(query: "ext:swift", limit: 1000, clientFilter: nil))

        // Only filters with toggles active -> no plain terms to wrap.
        let filtersOnly = SearchWindowQuery.compile(
            rawQuery: "ext:swift", mode: .names, options: SearchMatchOptions(matchCase: true))
        #expect(filtersOnly == .names(query: "ext:swift", limit: 1000, clientFilter: nil))

        // Single term with matchCase + wholeWord + metacharacter escaping.
        let single = SearchWindowQuery.compile(
            rawQuery: "Foo.bar ext:swift", mode: .names,
            options: SearchMatchOptions(matchCase: true, wholeWord: true))
        #expect(single == .names(query: #"ext:swift re:(?-i)\b(?:Foo\.bar)\b"#, limit: 1000, clientFilter: nil))

        // Regex + searchInPath + matchCase + wholeWord.
        let regexPath = SearchWindowQuery.compile(
            rawQuery: "src/[a-z]+", mode: .names,
            options: SearchMatchOptions(matchCase: true, wholeWord: true, regex: true, searchInPath: true))
        #expect(regexPath == .names(query: #"path:(?-i)\b(?:src/[a-z]+)\b"#, limit: 1000, clientFilter: nil))

        // Regex with spaces is quoted.
        let regexSpaced = SearchWindowQuery.compile(
            rawQuery: "foo bar", mode: .names, options: SearchMatchOptions(regex: true))
        #expect(regexSpaced == .names(query: #"re:"foo bar""#, limit: 1000, clientFilter: nil))

        // Multiple plain words with matchCase: daemon gets longest anchor + exact tokens, plus clientFilter.
        let multi = SearchWindowQuery.compile(
            rawQuery: "Foo AlphaBeta", mode: .names,
            options: SearchMatchOptions(matchCase: true, wholeWord: false))
        guard case let .names(q, _, filter) = multi else {
            Issue.record("expected names query")
            return
        }
        #expect(q == "re:(?-i)AlphaBeta 'Foo 'AlphaBeta")
        #expect(filter?.matches(path: "/p/Foo_AlphaBeta.txt") == true)
        #expect(filter?.matches(path: "/p/foo_AlphaBeta.txt") == false)

        // Multiple plain words with searchInPath + wholeWord.
        let multiPath = SearchWindowQuery.compile(
            rawQuery: "src main", mode: .names,
            options: SearchMatchOptions(wholeWord: true, searchInPath: true))
        guard case let .names(pq, _, pfilter) = multiPath else {
            Issue.record("expected path names query")
            return
        }
        #expect(pq == #"path:\b(?:main)\b"#)
        #expect(pfilter?.matches(path: "/repo/src/main.swift") == true)
        #expect(pfilter?.matches(path: "/repo/src/mainly.swift") == false)
        #expect(pfilter?.matches(path: "/repo/other/main.swift") == false)
    }

    @Test func compilesContentSymbolAndInlineGrepQueries() {
        #expect(SearchWindowQuery.compile(rawQuery: "ext:swift", mode: .content) == .empty)
        #expect(SearchWindowQuery.compile(rawQuery: "grep:", mode: .names) == .empty)

        let literal = SearchWindowQuery.compile(
            rawQuery: "needle ext:swift", mode: .content, chips: [SearchFilterChip(kind: .folder, value: "~/src")])
        #expect(literal == .grep(filters: "ext:swift in:~/src limit:1000", pattern: "needle", mode: .literal, limit: 1000))

        let caseWhole = SearchWindowQuery.compile(
            rawQuery: "foo.bar", mode: .content, options: SearchMatchOptions(matchCase: true, wholeWord: true))
        #expect(
            caseWhole
                == .grep(filters: "limit:1000", pattern: #"(?-i)\b(?:foo\.bar)\b"#, mode: .regex, limit: 1000))

        let ciRegex = SearchWindowQuery.compile(
            rawQuery: "fn\\s+\\w+", mode: .content, options: SearchMatchOptions(regex: true))
        #expect(ciRegex == .grep(filters: "limit:1000", pattern: #"(?i)fn\s+\w+"#, mode: .regex, limit: 1000))

        let sym = SearchWindowQuery.compile(rawQuery: "SearchModel", mode: .symbols)
        #expect(sym == .grep(filters: "limit:1000", pattern: "SearchModel", mode: .symbol, limit: 1000))

        let inline = SearchWindowQuery.compile(
            rawQuery: "ext:rs grep:TODO", mode: .names, options: SearchMatchOptions(matchCase: true))
        #expect(inline == .grep(filters: "ext:rs limit:1000", pattern: "(?-i)TODO", mode: .regex, limit: 1000))

        let explicitContentLimit = SearchWindowQuery.compile(rawQuery: "needle ext:swift limit:25", mode: .content)
        #expect(
            explicitContentLimit
                == .grep(filters: "ext:swift limit:25", pattern: "needle", mode: .literal, limit: 25))

        let clampedSymbolLimit = SearchWindowQuery.compile(rawQuery: "SearchModel limit:5000", mode: .symbols)
        #expect(
            clampedSymbolLimit
                == .grep(filters: "limit:5000", pattern: "SearchModel", mode: .symbol, limit: 1000))

        let customInlineDefault = SearchWindowQuery.compile(
            rawQuery: "ext:rs grep:TODO", mode: .names, defaultLimit: 200)
        #expect(
            customInlineDefault
                == .grep(filters: "ext:rs limit:200", pattern: "TODO", mode: .literal, limit: 200))
    }

    @Test func pageRequestClampsOffsetAndLimit() {
        let req = SearchWindowQuery.PageRequest(query: "test", mode: .names, offset: -5, limit: 0, sort: .defaultSort)
        #expect(req.offset == 0)
        #expect(req.limit == 1)
    }
}

@Suite struct SearchWindowRowAndSortTests {
    @Test func rowFormatsKindsSizesDisplaySafeNamesAndLines() {
        let file = SearchWindowRow(
            item: .file(Hit(path: "/tmp/a\u{202E}txt.pdf", kind: "file", size: 2048, mtime: 1_700_000_000, score: 50)))
        #expect(file.name.contains("\u{FFFD}"))
        #expect(file.kindLabel == "PDF")
        #expect(file.size == 2048)
        #expect(file.sizeFormatted != "–")
        #expect(file.modifiedAt != nil)
        #expect(!file.isDirectory)

        let dir = SearchWindowRow(item: .file(Hit(path: "/tmp/Folder", kind: "dir", size: 96, mtime: 0, score: 10)))
        #expect(dir.isDirectory)
        #expect(dir.size == nil)
        #expect(dir.sizeFormatted == "–")
        #expect(dir.modifiedAt == nil)
        #expect(dir.kindLabel == "Folder")

        let app = SearchWindowRow(item: .file(Hit(path: "/Applications/FSearch.app", kind: "dir", size: 0, mtime: 1, score: 10)))
        #expect(app.kindLabel == "Application")

        let link = SearchWindowRow(item: .file(Hit(path: "/tmp/shortcut", kind: "link", size: 12, mtime: 1, score: 10)))
        #expect(link.kindLabel == "Alias")

        let noExt = SearchWindowRow(item: .file(Hit(path: "/tmp/Makefile", kind: "file", size: 12, mtime: 1, score: 10)))
        #expect(noExt.kindLabel == "File")

        let line = SearchWindowRow(item: .line(path: "/tmp/main.swift", match: Match(line: 42, text: "  let x = 1  ")))
        #expect(line.id == "/tmp/main.swift:42")
        #expect(line.kindCode == "match")
        #expect(line.kindLabel == "SWIFT")
        #expect(line.lineNumber == 42)
        #expect(line.matchText == "let x = 1")
        #expect(line.size == nil && line.mtime == nil)
    }

    @Test func sortsEveryColumnAscendingDescendingAndBreaksTiesDeterministically() {
        let a = SearchWindowRow(item: .file(Hit(path: "/b/zeta.txt", kind: "file", size: 100, mtime: 300, score: 10)))
        let b = SearchWindowRow(item: .file(Hit(path: "/a/alpha.md", kind: "file", size: 500, mtime: 100, score: 90)))
        let dir = SearchWindowRow(item: .file(Hit(path: "/c/mid", kind: "dir", size: 0, mtime: 200, score: 50)))
        let rows = [a, b, dir]

        var dirToggle = SortDirection.ascending
        dirToggle.toggle()
        #expect(dirToggle == .descending)
        dirToggle.toggle()
        #expect(dirToggle == .ascending)

        #expect(
            SearchWindowRow.sort(rows, by: SearchWindowSort(column: .relevance, direction: .descending)).map(\.id) == [b.id, dir.id, a.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .name, direction: .ascending)).map(\.id) == [b.id, dir.id, a.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .name, direction: .descending)).map(\.id) == [a.id, dir.id, b.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .folder, direction: .ascending)).map(\.id) == [b.id, a.id, dir.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .size, direction: .ascending)).map(\.id) == [dir.id, a.id, b.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .size, direction: .descending)).map(\.id) == [b.id, a.id, dir.id])
        #expect(SearchWindowRow.sort(rows, by: SearchWindowSort(column: .kind, direction: .ascending)).map(\.id) == [dir.id, b.id, a.id])
        #expect(
            SearchWindowRow.sort(rows, by: SearchWindowSort(column: .modified, direction: .descending)).map(\.id) == [a.id, dir.id, b.id])

        // Tie-breaker by line number on same path.
        let l1 = SearchWindowRow(item: .line(path: "/p/a.swift", match: Match(line: 20, text: "b")))
        let l2 = SearchWindowRow(item: .line(path: "/p/a.swift", match: Match(line: 5, text: "a")))
        #expect(SearchWindowRow.sort([l1, l2], by: .defaultSort).map(\.lineNumber) == [5, 20])
    }

    @Test func sortsNaturalNamesIdenticalStringTiesAndLargeSharedDataset() {
        // Natural-number ordering on .name.
        let f10 = SearchWindowRow(item: .file(Hit(path: "/dir/file10.txt", kind: "file", size: 10, mtime: 10, score: 1)))
        let f2 = SearchWindowRow(item: .file(Hit(path: "/dir/file2.txt", kind: "file", size: 20, mtime: 20, score: 1)))
        #expect(
            SearchWindowRow.sort([f10, f2], by: SearchWindowSort(column: .name, direction: .ascending)).map(\.rawName)
                == ["file2.txt", "file10.txt"])
        #expect(
            SearchWindowRow.sort([f2, f10], by: SearchWindowSort(column: .name, direction: .descending)).map(\.rawName)
                == ["file10.txt", "file2.txt"])

        // Canonically equivalent NFC vs NFD strings must still follow localizedStandardCompare (NSForcedOrderingSearch).
        let nfc = SearchWindowRow(item: .file(Hit(path: "/a/caf\u{00E9}.txt", kind: "file", size: 1, mtime: 1, score: 1)))
        let nfd = SearchWindowRow(item: .file(Hit(path: "/z/cafe\u{0301}.txt", kind: "file", size: 1, mtime: 1, score: 1)))
        let expectedUnicodeAsc =
            nfc.rawName.localizedStandardCompare(nfd.rawName) == .orderedAscending ? [nfc.id, nfd.id] : [nfd.id, nfc.id]
        #expect(
            SearchWindowRow.sort([nfc, nfd], by: SearchWindowSort(column: .name, direction: .ascending)).map(\.id) == expectedUnicodeAsc)
        #expect(
            SearchWindowRow.sort([nfc, nfd], by: SearchWindowSort(column: .name, direction: .descending)).map(\.id)
                == expectedUnicodeAsc.reversed())

        // Equal-folder and equal-kind ties fall back to path ascending (both directions) and lineNumber ascending.
        let sameFolderB = SearchWindowRow(item: .file(Hit(path: "/shared/b.txt", kind: "file", size: 1, mtime: 1, score: 1)))
        let sameFolderA20 = SearchWindowRow(item: .line(path: "/shared/a.txt", match: Match(line: 20, text: "b")))
        let sameFolderA5 = SearchWindowRow(item: .line(path: "/shared/a.txt", match: Match(line: 5, text: "a")))
        let folderRows = [sameFolderB, sameFolderA20, sameFolderA5]
        let expectedTieIDs = [sameFolderA5.id, sameFolderA20.id, sameFolderB.id]
        for direction in [SortDirection.ascending, .descending] {
            #expect(
                SearchWindowRow.sort(folderRows, by: SearchWindowSort(column: .folder, direction: direction)).map(\.id) == expectedTieIDs)
        }

        let kindZ = SearchWindowRow(item: .file(Hit(path: "/z/one.txt", kind: "file", size: 1, mtime: 1, score: 1)))
        let kindA12 = SearchWindowRow(item: .line(path: "/a/two.txt", match: Match(line: 12, text: "b")))
        let kindA3 = SearchWindowRow(item: .line(path: "/a/two.txt", match: Match(line: 3, text: "a")))
        let kindRows = [kindZ, kindA12, kindA3]
        let expectedKindIDs = [kindA3.id, kindA12.id, kindZ.id]
        for direction in [SortDirection.ascending, .descending] {
            #expect(SearchWindowRow.sort(kindRows, by: SearchWindowSort(column: .kind, direction: direction)).map(\.id) == expectedKindIDs)
        }

        // 1,000-row dataset sharing a few folders and extensions sorts deterministically and monotonically.
        let folders = ["/root/alpha", "/root/beta", "/root/gamma", "/root/delta"]
        let exts = ["swift", "txt", "md", "json"]
        let dataset: [SearchWindowRow] = (0..<1000).map { i in
            let idx = (i * 37 + 13) % 1000
            let folder = folders[idx % folders.count]
            let ext = exts[(idx / folders.count) % exts.count]
            let path = "\(folder)/item\((idx / 16) % 15).\(ext)"
            if idx < 240 {
                return SearchWindowRow(
                    item: .file(Hit(path: path, kind: "file", size: UInt64(idx), mtime: Int64(idx), score: Int32(idx))))
            }
            return SearchWindowRow(item: .line(path: path, match: Match(line: idx + 1, text: "line \(idx)")))
        }

        for column in [SearchWindowColumn.folder, .kind, .name] {
            for direction in [SortDirection.ascending, .descending] {
                let spec = SearchWindowSort(column: column, direction: direction)
                let sorted1 = SearchWindowRow.sort(dataset, by: spec)
                let sorted2 = SearchWindowRow.sort(dataset.reversed(), by: spec)
                #expect(sorted1.count == 1000)
                #expect(sorted1.map(\.id) == sorted2.map(\.id))

                for pair in zip(sorted1, sorted1.dropFirst()) {
                    let key: (SearchWindowRow) -> String = { row in
                        switch column {
                        case .folder: row.rawFolder
                        case .kind: row.kindLabel
                        case .name: row.rawName
                        default: fatalError("unexpected column")
                        }
                    }
                    let cmp = key(pair.0).localizedStandardCompare(key(pair.1))
                    if cmp == .orderedSame {
                        if pair.0.path != pair.1.path {
                            #expect(pair.0.path < pair.1.path)
                        } else {
                            #expect((pair.0.lineNumber ?? 0) <= (pair.1.lineNumber ?? 0))
                        }
                    } else if direction == .ascending {
                        #expect(cmp == .orderedAscending)
                    } else {
                        #expect(cmp == .orderedDescending)
                    }
                }
            }
        }
    }

    @Test func statusSummariesHandleCountsCapsAndSelections() {
        #expect(SearchWindowStatus.resultSummary(count: 0, hitCap: false) == "0 results")
        #expect(SearchWindowStatus.resultSummary(count: 1, hitCap: false) == "1 result")
        #expect(SearchWindowStatus.resultSummary(count: 42, hitCap: false) == "42 results")
        #expect(SearchWindowStatus.resultSummary(count: 1000, hitCap: true) == "\(1000.formatted()) results (limit reached)")

        #expect(SearchWindowStatus.selectionSummary(selected: []) == nil)
        let f = SearchWindowRow(item: .file(Hit(path: "/a.txt", kind: "file", size: 2000, mtime: 1, score: 1)))
        let d = SearchWindowRow(item: .file(Hit(path: "/dir", kind: "dir", size: 0, mtime: 1, score: 1)))
        #expect(SearchWindowStatus.selectionSummary(selected: [f])?.contains("1 selected") == true)
        #expect(SearchWindowStatus.selectionSummary(selected: [d]) == "1 selected")
    }
}

@Suite struct SavedSearchStoreTests {
    private func freshStore() -> (SavedSearchStore, String) {
        let suite = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mt.fsearchkit.tests.saved.\(UUID().uuidString)").path
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SavedSearchStore(defaults: defaults), suite)
    }

    private func cleanup(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }

    @Test func builtInPresetsAndCrudLifecycle() {
        #expect(SavedSearch.builtInPresets.count == 5)
        #expect(SavedSearch.builtInPresets.allSatisfy { $0.isBuiltIn })

        let (store, suite) = freshStore()
        defer { cleanup(suite) }

        #expect(store.load().isEmpty)
        let added = store.add(SavedSearch(name: "  Swift TODOs  ", query: "TODO", mode: .content))
        #expect(added.count == 1)
        #expect(added[0].name == "Swift TODOs")
        #expect(!added[0].isBuiltIn)

        // Blank name ignored on add and rename.
        #expect(store.add(SavedSearch(name: "   ")).count == 1)
        #expect(store.rename(id: added[0].id, to: "   ")[0].name == "Swift TODOs")

        let renamed = store.rename(id: added[0].id, to: "Renamed")
        #expect(renamed[0].name == "Renamed")
        #expect(store.load()[0].name == "Renamed")

        // Built-in items are not persisted by save().
        store.save(SavedSearch.builtInPresets + renamed)
        #expect(store.load().count == 1)

        #expect(store.delete(id: added[0].id).isEmpty)
        store.clear()
        #expect(store.load().isEmpty)

        // Corrupt JSON returns empty safely.
        UserDefaults(suiteName: suite)!.set(Data("not-json".utf8), forKey: SavedSearchStore.storageKey)
        #expect(store.load().isEmpty)
    }
}

@Suite @MainActor struct SearchWindowModelTests {
    private final class StubBackend: SearchBackend, @unchecked Sendable {
        struct State {
            var searches: [(String, Int)] = []
            var greps: [(String, String, GrepMode)] = []
            var onSearch: @Sendable (String, Int) async throws -> SearchReply = { _, _ in SearchReply(tookUs: 100, hits: []) }
            var onGrep: @Sendable (String, String, GrepMode) async throws -> GrepReply = { _, _, _ in GrepReply(tookUs: 200, files: []) }
        }
        let state = Mutex(State())

        func search(_ query: String, limit: Int) async throws -> SearchReply {
            let fn = state.withLock { s -> @Sendable (String, Int) async throws -> SearchReply in
                s.searches.append((query, limit))
                return s.onSearch
            }
            return try await fn(query, limit)
        }

        func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
            let fn = state.withLock { s -> @Sendable (String, String, GrepMode) async throws -> GrepReply in
                s.greps.append((q, pattern, mode))
                return s.onGrep
            }
            return try await fn(q, pattern, mode)
        }

        func status() async throws -> DaemonStatus { DaemonStatus(entries: 0) }
        func ping() async throws {}
    }

    @Test func refreshesSortsManagesChipsAndSnapshots() async {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onSearch = { _, _ in
                SearchReply(
                    tookUs: 500,
                    hits: [
                        Hit(path: "/p/b.txt", kind: "file", size: 10, mtime: 100, score: 100),
                        Hit(path: "/p/a.txt", kind: "file", size: 90, mtime: 200, score: 50),
                    ])
            }
        }
        let model = SearchWindowModel(names: backend, content: backend)
        var logged: [SearchModel.LogEntry] = []
        var settled: [SearchPhase] = []
        model.onSearched = { logged.append($0) }
        model.onSettled = { settled.append($0) }

        #expect(model.pageRequest.query.isEmpty)
        await model.refresh()
        #expect(model.phase == .idle && model.rows.isEmpty)

        let chip = SearchFilterChip(kind: .ext, value: "txt")
        model.addChip(chip)
        model.addChip(chip)  // deduped
        #expect(model.chips.count == 1)
        model.toggleChip(chip)
        #expect(model.chips.isEmpty)
        model.toggleChip(chip)
        #expect(model.chips.count == 1)

        model.query = "report"
        #expect(model.pageRequest.query == "report ext:txt")
        await model.refresh()
        #expect(model.phase == .results)
        #expect(model.rows.map(\.rawName) == ["b.txt", "a.txt"])
        #expect(model.lastTookUs == 500)
        #expect(model.lastRoundTripMs != nil)
        #expect(!model.hitCap)
        #expect(logged.count == 1 && settled == [.results])

        // Re-sorting happens immediately in memory without re-querying.
        let searchesBeforeSort = backend.state.withLock { $0.searches.count }
        model.sort = SearchWindowSort(column: .name, direction: .ascending)
        #expect(model.rows.map(\.rawName) == ["a.txt", "b.txt"])
        #expect(backend.state.withLock { $0.searches.count } == searchesBeforeSort)

        // Snapshot & apply saved search.
        let snap = model.snapshot(name: "Reports")
        model.clearFilters()
        #expect(model.chips.isEmpty && !model.options.hasAnyOption)
        model.apply(snap)
        #expect(model.query == "report" && model.chips == [chip] && model.sort.column == .name)
    }

    @Test func handlesHalfTypedFiltersContentModeAccentsAndErrors() async {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onSearch = { q, _ in
                SearchReply(tookUs: 100, hits: [Hit(path: "/p/\(q).txt", kind: "file", size: 1, mtime: 1, score: 10)])
            }
            s.onGrep = { _, _, _ in
                GrepReply(
                    tookUs: 300, complete: false,
                    files: [FileMatches(path: "/p/main.swift", matches: [Match(line: 7, text: "let x = 1")])])
            }
        }
        let model = SearchWindowModel(names: backend, content: backend)

        // Initial half-typed clears.
        model.query = "size:"
        await model.refresh()
        #expect(model.phase == .idle && model.rows.isEmpty)

        // Extending a settled query with a half-typed filter keeps previous rows.
        model.query = "alpha"
        await model.refresh()
        #expect(model.rows.count == 1)
        model.query = "alpha size:"
        await model.refresh()
        #expect(model.rows.count == 1)

        // Optimistic row removal drops trashed paths immediately without waiting on FSEvents.
        model.removeRows(matchingPaths: ["/p/alpha.txt"])
        #expect(model.rows.isEmpty)
        model.removeRows(matchingPaths: [])

        // Cancelled in-flight search followed by a half-typed filter must NOT stay stranded in .loading.
        let slow = StubBackend()
        let (started, startedCont) = AsyncStream.makeStream(of: Void.self)
        slow.state.withLock { s in
            s.onSearch = { _, _ in
                startedCont.yield()
                try await Task.sleep(for: .seconds(30))
                return SearchReply(tookUs: 50, hits: [])
            }
        }
        let slowModel = SearchWindowModel(names: slow, content: slow)
        slowModel.query = "alpha"
        let inFlight = Task { await slowModel.refresh() }
        var startedIt = started.makeAsyncIterator()
        _ = await startedIt.next()
        #expect(slowModel.phase == .loading)
        inFlight.cancel()
        await inFlight.value
        slowModel.query = "alpha size:"
        await slowModel.refresh()
        #expect(slowModel.phase == .idle)

        // Accented query searches both NFC & NFD forms and merges.
        model.query = "caf\u{00E9}"
        await model.refresh()
        #expect(backend.state.withLock { $0.searches.count } >= 3)

        // Content mode reports incomplete reply as hitCap.
        model.mode = .content
        model.query = "let"
        #expect(model.pageRequest.mode == .content)
        await model.refresh()
        #expect(model.phase == .results && model.hitCap && model.rows.first?.lineNumber == 7)

        // Indexing, DaemonError, and generic errors map cleanly.
        model.mode = .names
        model.query = "err"
        backend.state.withLock { $0.onSearch = { _, _ in throw DaemonError.indexing("building") } }
        await model.refresh()
        #expect(model.phase == .indexing)

        backend.state.withLock { $0.onSearch = { _, _ in throw DaemonError.disconnected } }
        await model.refresh()
        #expect(model.phase == .failed(.disconnected))

        struct CustomErr: Error {}
        backend.state.withLock { $0.onSearch = { _, _ in throw CustomErr() } }
        await model.refresh()
        if case .failed(.badReply) = model.phase {} else { Issue.record("expected badReply, got \(model.phase)") }
    }

    @Test func newerRefreshCancelsStaleInFlightSearch() async {
        let backend = StubBackend()
        let (started, startedCont) = AsyncStream.makeStream(of: Void.self)
        backend.state.withLock { s in
            s.onSearch = { q, _ in
                if q == "slow" {
                    startedCont.yield()
                    try await Task.sleep(for: .seconds(30))
                }
                return SearchReply(tookUs: 50, hits: [Hit(path: "/p/\(q).txt", kind: "file", size: 1, mtime: 1, score: 1)])
            }
        }
        let model = SearchWindowModel(names: backend, content: backend)
        model.query = "slow"
        let first = Task { await model.refresh() }
        var startedIt = started.makeAsyncIterator()
        _ = await startedIt.next()
        model.query = "fast"
        await model.refresh()
        await first.value
        #expect(model.rows.map(\.rawName) == ["fast.txt"])
    }

    @Test(.enabled(if: RealDaemon.binary != nil, "Vendor/fsearch not built"))
    func matchTogglesWorkEndToEndAgainstRealDaemon() async throws {
        let daemon = try RealDaemon(files: [
            "Alpha/Target.swift": "let Target = 1\nlet target = 2\nlet TargetMore = 3\n",
            "Beta/target.swift": "let target = 2\n",
            "Beta/TargetExtra.swift": "let Target = 4\n",
        ])
        defer { withExtendedLifetime(daemon) {} }
        let names = DaemonClient(socketPath: daemon.socketPath, timeout: 5)
        let content = DaemonClient(socketPath: daemon.socketPath, timeout: 5)
        var ready = false
        for _ in 0..<100 {
            if let s = try? await names.status(), s.entries >= 5, s.contentDocs >= 3, s.contentPending == 0 {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(ready, "RealDaemon failed to index fixture files")

        let model = SearchWindowModel(names: names, content: content)

        // Match Case + Whole Word on names: matches only "Target.swift", not "target.swift" or "TargetExtra.swift".
        model.query = "Target"
        model.options = SearchMatchOptions(matchCase: true, wholeWord: true)
        await model.refresh()
        #expect(model.rows.map(\.rawName) == ["Target.swift"])

        // Search in Path: matches only inside Alpha/.
        model.query = "Alpha/Target"
        model.options = SearchMatchOptions(matchCase: true, searchInPath: true)
        await model.refresh()
        #expect(model.rows.count == 1)
        #expect(model.rows[0].path.contains("/Alpha/Target.swift"))

        // Inside Files + Match Case + Whole Word: matches line 1 ("let Target = 1") and Alpha/TargetExtra line 1, not "target" or "TargetMore".
        model.mode = .content
        model.query = "Target"
        model.options = SearchMatchOptions(matchCase: true, wholeWord: true)
        model.chips = [SearchFilterChip(kind: .ext, value: "swift")]
        await model.refresh()
        #expect(model.rows.count == 2)
        #expect(model.rows.allSatisfy { $0.matchText?.contains("Target = ") == true })
    }

    @Test func grepModesInjectDefaultLimitAndFlagHitCapAtFileLimit() async {
        let backend = StubBackend()
        let model = SearchWindowModel(names: backend, content: backend)

        model.mode = .content
        model.query = "needle"
        #expect(model.pageRequest.limit == 1000)
        await model.refresh()

        model.mode = .symbols
        model.query = "SearchModel"
        #expect(model.pageRequest.limit == 1000)
        await model.refresh()

        let recordedGreps = backend.state.withLock { $0.greps }
        #expect(recordedGreps.count == 2)
        #expect(recordedGreps[0].0 == "limit:1000")
        #expect(recordedGreps[0].2 == .literal)
        #expect(recordedGreps[1].0 == "limit:1000")
        #expect(recordedGreps[1].2 == .symbol)

        backend.state.withLock { s in
            s.greps.removeAll()
            s.onGrep = { _, _, _ in
                let files = (0..<19).map { i in
                    FileMatches(path: "/p/f\(i).swift", matches: [Match(line: 1, text: "needle")])
                }
                return GrepReply(tookUs: 100, complete: true, files: files)
            }
        }
        model.mode = .content
        model.query = "needle limit:20"
        #expect(model.pageRequest.limit == 20)
        await model.refresh()
        let underCapGreps = backend.state.withLock { $0.greps }
        #expect(underCapGreps.last?.0 == "limit:20")
        #expect(!underCapGreps.last!.0.contains("limit:1000"))
        #expect(model.rows.count == 19)
        #expect(!model.hitCap)

        backend.state.withLock { s in
            s.onGrep = { _, _, _ in
                let files = (0..<20).map { i in
                    FileMatches(path: "/p/f\(i).swift", matches: [Match(line: 1, text: "needle")])
                }
                return GrepReply(tookUs: 100, complete: true, files: files)
            }
        }
        await model.refresh()
        #expect(model.rows.count == 20)
        #expect(model.hitCap)
    }

    @Test(.enabled(if: RealDaemon.binary != nil, "Vendor/fsearch not built"))
    func grepExceeds50FileDaemonDefaultAndFlagsExplicitLimitHitCapAgainstRealDaemon() async throws {
        var files: [String: String] = [:]
        for i in 0..<60 {
            files["f\(i).txt"] = "shared_needle_token\n"
        }
        let daemon = try RealDaemon(files: files)
        defer { withExtendedLifetime(daemon) {} }
        let names = DaemonClient(socketPath: daemon.socketPath, timeout: 5)
        let content = DaemonClient(socketPath: daemon.socketPath, timeout: 5)
        var ready = false
        for _ in 0..<100 {
            if let s = try? await names.status(), s.entries >= 60, s.contentDocs >= 60, s.contentPending == 0 {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(ready, "RealDaemon failed to index 60 fixture files")

        let model = SearchWindowModel(names: names, content: content)
        model.mode = .content
        model.query = "shared_needle_token"
        await model.refresh()
        #expect(model.rows.count == 60)
        #expect(!model.hitCap)

        model.query = "shared_needle_token limit:10"
        await model.refresh()
        #expect(model.rows.count == 10)
        #expect(model.hitCap)
    }
}
