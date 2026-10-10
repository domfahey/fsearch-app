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

    private var shown: [ResultItem] {
        model.query.isEmpty && model.mode == .names
            ? app.recents.paths.map { .file(Hit(path: $0, kind: "file", size: 0, mtime: 0, score: 0)) }
            : model.items
    }

    private var rowCount: Int { PanelRows.count(files: shown.count, query: model.query, mode: model.mode) }
    /// Content and symbol rows highlight the pattern, not the filters.
    private var highlightQuery: String { model.mode == .names ? model.query : QuerySplit.split(model.query).pattern }

    var body: some View {
        VStack(spacing: 0) {
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
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let msg = UserMessage.forPhase(model.phase) {
                        Text(msg).foregroundStyle(.secondary).padding(16)
                    }
                    if !shown.isEmpty {
                        section(model.query.isEmpty ? "Recent" : (model.mode == .names ? "Files" : "Inside files"))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                            ResultRow(item: item, query: highlightQuery, selected: i == state.selection)
                                .onTapGesture(count: 2) { onEffect(.open(i), shown) }
                                .onTapGesture { state.selection = i }
                                .draggable(URL(fileURLWithPath: item.path))
                        }
                    }
                    if model.mode == .names && !model.query.isEmpty {
                        section("Use “\(model.query)” with…")
                        fallback("Search inside files", "doc.text.magnifyingglass", selected: state.selection == shown.count) { switchMode(.content) }
                        fallback("Find definitions", "function", selected: state.selection == shown.count + 1) { switchMode(.symbols) }
                    }
                }
                .padding(.bottom, 6)
            }
            Divider()
            HStack(spacing: 14) {
                if app.debugMode, let us = model.lastTookUs {
                    Text(String(format: "%.1f ms · %d results", Double(us) / 1000, model.items.count)).foregroundStyle(.secondary)
                }
                Spacer()
                hint(model.mode == .names ? "Open" : "Open at line", "↵")
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

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
    }

    private func fallback(_ t: String, _ icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).frame(width: 22); Text(t) }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle()).onTapGesture(perform: action)
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
        state.query = model.query; state.mode = model.mode; state.count = rowCount
        let cmd = press.modifiers.contains(.command), shift = press.modifiers.contains(.shift), ctrl = press.modifiers.contains(.control)
        let key: PanelKey? = switch (press.key, cmd, shift, ctrl) {
        case (.upArrow, _, _, _), (KeyEquivalent("p"), false, false, true): .up
        case (.downArrow, _, _, _), (KeyEquivalent("n"), false, false, true): .down
        case (.return, true, _, _): .cmdEnter
        case (.return, false, _, _): .enter
        case (.escape, _, _, _): .escape
        case (KeyEquivalent("y"), true, false, _): .cmdY
        case (KeyEquivalent("c"), true, true, _): .cmdShiftC
        case (KeyEquivalent("k"), true, false, _): .cmdK
        case (.delete, false, _, _) where model.query.isEmpty: .backspaceOnEmpty
        default: press.characters.first.flatMap { $0.wholeNumberValue }.flatMap { cmd ? PanelKey.cmdDigit($0) : nil }
        }
        guard let key else { return .ignored }
        let effect = reduce(&state, key)
        // A query change refreshes through .onChange; only a mode change alone needs it here.
        let modeChanged = model.mode != state.mode
        let queryChanged = model.query != state.query
        model.query = state.query; model.mode = state.mode
        if modeChanged && !queryChanged { Task { await model.refresh() } }
        // Rows past the files are the "use with..." rows: Return switches mode, other actions don't apply.
        switch effect {
        case let .open(i) where i >= shown.count:
            if let m = PanelRows.row(at: i, files: shown.count, query: model.query, mode: model.mode)?.mode { switchMode(m) }
        case let .reveal(i), let .quickLook(i), let .copyPath(i), let .showActions(i):
            if i < shown.count { onEffect(effect, shown) }
        default:
            onEffect(effect, shown)
        }
        return .handled
    }
}
