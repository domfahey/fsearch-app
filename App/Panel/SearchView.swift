import FSearchKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @Bindable var model: SearchModel
    @State var state: PanelState
    @FocusState private var focused: Bool
    let onEffect: (PanelEffect, [ResultItem]) -> Void
    let onSelect: (Int) -> Void
    let onCommand: (AppCommand) -> Void

    private var shown: [ResultItem] {
        // Reading the generation makes a trash or open re-read the recents.
        _ = app.recentsGeneration
        return model.query.isEmpty && model.mode == .names
            ? app.recents.paths.map { .file(Hit(path: $0, kind: "file", size: 0, mtime: 0, score: 0)) }
            : model.items
    }

    /// Built once per body evaluation and shared by the lookups below.
    private var rows: PanelRows { PanelRows(files: shown.count, query: model.query, mode: model.mode) }
    /// Content and symbol rows highlight the pattern, not the filters.
    private var highlightQuery: String {
        if model.mode != .names { return QuerySplit.split(model.query).pattern }
        return QuerySplit.contentSearch(model.query)?.pattern ?? model.query
    }
    private var showsLines: Bool { if case .line = shown.first { true } else { false } }

    var body: some View {
        let rows = rows
        let commands = rows.commands.count
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                if model.mode != .names {
                    Text(model.mode == .content ? "Inside files" : "Definitions")
                        .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
                TextField("Search files", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 17))
                    .focused($focused)
                    .accessibilityIdentifier("searchField")
                    .onChange(of: model.query) {
                        state.selection = 0
                        Task { await model.refresh() }
                    }
                if app.debugMode { Circle().fill(.orange).frame(width: 6, height: 6).help("Debug mode") }
            }
            .padding(14)
            DaemonMessageLine(model: model, daemon: app.daemon)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if case .failed(.daemon) = model.phase {} else if let msg = UserMessage.forPhase(model.phase) {
                        Text(msg).foregroundStyle(.secondary).padding(16)
                    }
                    if QuerySyntax.isCheatSheet(model.query) {
                        cheatSheet
                    }
                    if !rows.commands.isEmpty {
                        section("FSearch")
                        ForEach(Array(rows.commands.enumerated()), id: \.offset) { i, c in
                            fallback(c.title, c.symbol, selected: state.selection == i) { onCommand(c) }
                                .accessibilityIdentifier("command-\(c.title)")
                        }
                    }
                    if !shown.isEmpty {
                        section(model.query.isEmpty ? "Recent" : (showsLines ? "Inside files" : "Files"))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                            ResultRow(item: item, query: highlightQuery, selected: commands + i == state.selection)
                                .onTapGesture(count: 2) { onEffect(.open(i), shown) }
                                .onTapGesture { state.selection = commands + i }
                                .draggable(URL(fileURLWithPath: item.path))
                        }
                    }
                    if rows.hasFallbacks {
                        // UI tests press ↵ on a fallback only once the search is done and the row is selected.
                        section("Use “\(model.query)” with…")
                            .accessibilityIdentifier("fallbacks")
                            .accessibilityValue(model.phase == .loading ? "searching" : "done")
                        fallback("Search inside files", "doc.text.magnifyingglass", selected: state.selection == commands + shown.count) { switchMode(.content) }
                            .accessibilityIdentifier("fallback-content")
                        fallback("Find definitions", "function", selected: state.selection == commands + shown.count + 1) { switchMode(.symbols) }
                            .accessibilityIdentifier("fallback-symbols")
                    }
                }
                .padding(.bottom, 6)
            }
            Divider()
            HStack(spacing: 14) {
                if app.debugMode, let us = model.lastTookUs {
                    Text(String(format: "%.1f ms · %d results", Double(us) / 1000, model.items.count)).foregroundStyle(.secondary)
                }
                if let err = app.actionError {
                    Text(err).foregroundStyle(.red).lineLimit(1).accessibilityIdentifier("actionError")
                }
                Spacer()
                hint(showsLines ? "Open at line" : "Open", "↵")
                hint("Reveal in Finder", "⌘↵")
                hint("Actions", "⌘K")
            }
            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 680, height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { focused = true }
        .onChange(of: state.selection) { onSelect(state.selection) }
        .onKeyPress(phases: .down) { press in handle(press) }
    }

    /// "?" in the field: the query syntax instead of results.
    private var cheatSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Query syntax")
            ForEach(QuerySyntax.cheatSheet, id: \.syntax) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.syntax).font(.system(size: 13, design: .monospaced)).frame(width: 220, alignment: .leading)
                    Text(row.meaning).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 3)
            }
        }
        .accessibilityIdentifier("cheatSheet")
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func fallback(_ t: String, _ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).frame(width: 22); Text(t) }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).onTapGesture(perform: action)
            // A container (its Text stays findable) whose value says whether ↵ would run it.
            .accessibilityElement(children: .contain)
            .accessibilityValue(selected ? "selected" : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hint(_ t: String, _ k: String) -> some View {
        HStack(spacing: 4) { Text(t); Text(k).padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5))) }
    }

    private func switchMode(_ m: SearchMode) {
        model.mode = m
        state.selection = 0
        Task { await model.refresh() }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let rows = rows
        state.query = model.query; state.mode = model.mode; state.count = rows.count; state.files = shown.count
        state.commands = rows.commands.count
        guard let key = PanelInput.key(for: PanelInput.Press(press), queryIsEmpty: model.query.isEmpty) else { return .ignored }
        let effect = reduce(&state, key)
        // A query change refreshes through .onChange; only a mode change alone needs it here.
        let modeChanged = model.mode != state.mode
        let queryChanged = model.query != state.query
        model.query = state.query; model.mode = state.mode
        if modeChanged && !queryChanged { Task { await model.refresh() } }
        switch PanelInput.route(effect, rows: rows) {
        case let .perform(e): onEffect(e, shown)
        case let .switchMode(m): switchMode(m)
        case let .runCommand(c): onCommand(c)
        case .ignore: break
        }
        return .handled
    }
}
