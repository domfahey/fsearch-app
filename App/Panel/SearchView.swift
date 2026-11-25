import FSearchKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// The global shortcut that shows the panel; ⌥ Space unless the user changed it.
    static let togglePanel = Self("togglePanel", default: .init(.space, modifiers: [.option]))
}

/// Observable holder for the panel's selection state and focus trigger, letting
/// ``PanelController`` reuse a single ``SearchView`` hosting view across reopens.
@MainActor @Observable
final class PanelViewState {
    var state: PanelState
    var focusTrigger = 0

    init(state: PanelState = PanelState()) { self.state = state }

    func resume(_ resumed: PanelState) {
        state = resumed
        focusTrigger += 1
    }
}

/// The panel's contents: the search field, the rows (files, commands, fallbacks) and the key hints.
///
/// Rows follow ``PanelRows``: files first, then app commands, then the two fallbacks.
struct SearchView: View {
    @EnvironmentObject var app: AppState
    @Bindable var model: SearchModel
    /// The keyboard state, reduced by ``PanelState/reduce(_:)``.
    @Bindable var viewState: PanelViewState
    @FocusState private var focused: Bool
    /// A result key pressed before the rows answered the query, run once they do.
    let held: HeldKeyBox
    /// Keys from outside the view: ↑/↓ pressed in Quick Look.
    let keys: PanelKeyFeed
    /// Where the rows are laid out, for ⌘K's menu.
    let geometry: PanelGeometry
    /// The FSearch menu (⌘/ or the footer's gear), owned by the controller.
    let menu: AppMenuState
    /// Whether the panel is on screen; a hidden panel never replays a held key.
    let isVisible: () -> Bool
    /// What ↵ does on the selected row, remembered per row.
    @State private var revealCache = RevealCache()
    let onEffect: (PanelEffect, [ResultItem]) -> Void
    let onSelect: (Int) -> Void
    let onCommand: (AppCommand) -> Void

    init(
        model: SearchModel, viewState: PanelViewState, held: HeldKeyBox, keys: PanelKeyFeed, geometry: PanelGeometry,
        menu: AppMenuState, isVisible: @escaping () -> Bool,
        onEffect: @escaping (PanelEffect, [ResultItem]) -> Void, onSelect: @escaping (Int) -> Void,
        onCommand: @escaping (AppCommand) -> Void
    ) {
        self.model = model
        self.viewState = viewState
        self.held = held
        self.keys = keys
        self.geometry = geometry
        self.menu = menu
        self.isVisible = isVisible
        self.onEffect = onEffect
        self.onSelect = onSelect
        self.onCommand = onCommand
    }

    init(
        model: SearchModel, state: PanelState, held: HeldKeyBox, keys: PanelKeyFeed, geometry: PanelGeometry,
        menu: AppMenuState, isVisible: @escaping () -> Bool,
        onEffect: @escaping (PanelEffect, [ResultItem]) -> Void, onSelect: @escaping (Int) -> Void,
        onCommand: @escaping (AppCommand) -> Void
    ) {
        self.init(
            model: model, viewState: PanelViewState(state: state), held: held, keys: keys, geometry: geometry, menu: menu,
            isVisible: isVisible, onEffect: onEffect, onSelect: onSelect, onCommand: onCommand)
    }

    private var selection: Int { viewState.state.selection }

    /// The file rows: recents for an empty query, the search results otherwise.
    private var shown: [ResultItem] {
        // Reading the generation makes a trash or open re-read the recents.
        _ = app.recentsGeneration
        return model.query.isEmpty && model.mode == .names
            ? app.recents.entries.map { .file(Hit(path: $0.path, kind: $0.isDirectory ? "dir" : "file", size: 0, mtime: 0, score: 0)) }
            : model.items
    }

    /// Content and symbol rows highlight the pattern, not the filters.
    private var highlightQuery: String {
        if model.mode != .names { return QuerySplit.split(model.query).pattern }
        return QuerySplit.contentSearch(model.query)?.pattern ?? model.query
    }

    var body: some View {
        let shown = self.shown
        let rows = PanelRows(files: shown.count, query: model.query, mode: model.mode)
        let highlightQuery = self.highlightQuery
        let showsLines: Bool = if case .line = shown.first { true } else { false }
        let selectedItem = shown.indices.contains(selection) ? shown[selection] : nil
        let selectedRevealsOnReturn = selectedItem.map { revealCache.revealsOnReturn($0, editor: app.editor) } ?? false
        let selectedOpensAtLine = selectedItem.map { revealCache.opensAtLine($0, editor: app.editor) } ?? false
        let footer = PanelInput.footerHints(
            selection: selection, shown: shown, rows: rows, revealsOnReturn: selectedRevealsOnReturn, opensAtLine: selectedOpensAtLine)
        let commandsStart = shown.count
        let fallbacksStart = shown.count + rows.commands.count
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
                        viewState.state.selection = 0
                        held.key.cancel()  // a key held for the old query never runs on the new one
                        Task { await model.refresh() }
                    }
                if app.debugMode { Circle().fill(.orange).frame(width: 6, height: 6).help("Debug mode") }
            }
            .padding(14)
            .onPanelFrame { geometry.field = $0 }
            DaemonMessageLine(model: model, daemon: app.daemon)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if case .failed(.daemon) = model.phase {
                        } else {
                            PhaseMessage(model: model, daemon: app.daemon)
                        }
                        if QuerySyntax.isCheatSheet(model.query) {
                            cheatSheet
                        }
                        if !shown.isEmpty {
                            section(model.query.isEmpty ? "Recent" : (showsLines ? "Inside files" : "Files"))
                            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                                ResultRow(item: item, query: highlightQuery, selected: i == selection) { onEffect(.open(i), shown) }
                                    .id(item.id)
                                    .onPanelFrame { geometry.rows[item.id] = $0 }
                                    .onDisappear { geometry.rows[item.id] = nil }
                                    .onTapGesture(count: 2) { onEffect(.open(i), shown) }
                                    .onTapGesture { viewState.state.selection = i }
                                    .draggable(URL(fileURLWithPath: item.path))
                            }
                        }
                        // Below the files, so ↵ after "set" still opens the top file.
                        if !rows.commands.isEmpty {
                            section("FSearch")
                            ForEach(Array(rows.commands.enumerated()), id: \.offset) { i, c in
                                fallback(c.title, c.symbol, selected: selection == commandsStart + i) { onCommand(c) }
                                    .accessibilityIdentifier("command-\(c.title)")
                                    .id("command-\(c.title)")
                            }
                        }
                        if rows.hasFallbacks {
                            // UI tests press ↵ on a fallback only once the search is done and the row is selected.
                            section("Use “\(model.query)” with…")
                                .accessibilityIdentifier("fallbacks")
                                .accessibilityValue(model.phase == .loading ? "searching" : "done")
                            fallback("Search inside files", "doc.text.magnifyingglass", selected: selection == fallbacksStart) {
                                switchMode(.content)
                            }
                            .accessibilityIdentifier("fallback-content")
                            .id("fallback-content")
                            fallback("Find definitions", "function", selected: selection == fallbacksStart + 1) {
                                switchMode(.symbols)
                            }
                            .accessibilityIdentifier("fallback-symbols")
                            .id("fallback-symbols")
                        }
                    }
                    .padding(.bottom, 6)
                }
                .onPanelFrame { geometry.list = $0 }
                // The keyboard selection stays in view (anchor nil: the least scrolling).
                .onChange(of: viewState.state.selection) {
                    let current = self.shown
                    let currentRows = PanelRows(files: current.count, query: model.query, mode: model.mode)
                    if let id = PanelInput.rowID(at: viewState.state.selection, shown: current, rows: currentRows) { proxy.scrollTo(id) }
                }
            }
            Divider()
            HStack(spacing: 14) {
                AppMenuButton(menu: menu)
                if app.debugMode, let us = model.lastTookUs {
                    Text(String(format: "%.1f ms · %d results", Double(us) / 1000, model.items.count)).foregroundStyle(.secondary)
                }
                if let err = app.actionError {
                    Text(err).foregroundStyle(.red).lineLimit(1).accessibilityIdentifier("actionError")
                }
                Spacer()
                switch footer {
                case .none:
                    EmptyView()
                case .command:
                    hint("Open", "↵")
                case .fallback:
                    hint("Search", "↵")
                case .launchable:
                    hint("Reveal in Finder", "↵")
                    Text("⌘K → Open to launch").foregroundStyle(.secondary).accessibilityIdentifier("launchHint")
                    hint("Actions", "⌘K")
                case let .file(openAtLine):
                    hint(openAtLine ? "Open at line" : "Open", "↵")
                    hint("Reveal in Finder", "⌘↵")
                    hint("Actions", "⌘K")
                }
            }
            .font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 680, height: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .coordinateSpace(.named(PanelGeometry.space))
        .onAppear { focused = true }
        .onChange(of: viewState.focusTrigger) { focused = true }
        .onChange(of: viewState.state.selection) { onSelect(viewState.state.selection) }
        // An open preview follows the selected file: a new selection, or new rows under the same one.
        .onChange(of: PanelInput.previewPath(at: selection, shown: shown, rows: rows)) { _, path in
            QuickLookSource.shared.follow(path.map(FileActions.url))
        }
        // ↑/↓ pressed in Quick Look, which holds the keyboard while it is up.
        .onChange(of: keys.last) { if isVisible() && !menu.isOpen, let k = keys.last?.key { act(k) } }
        .onChange(of: model.mode) { held.key.cancel() }
        .overlay(alignment: .bottomLeading) { AppMenuOverlay(menu: menu) { AppMenuActions.run($0, app: app) } }
        // The menu's field had the keyboard: give it back to the search field.
        .onChange(of: menu.isOpen) { _, open in if !open { focused = true } }
        // The results for the query in the box arrived: run a key held for them.
        .onChange(of: PanelInput.answer(model)) { old, new in
            geometry.rowsChanged(keeping: Set(self.shown.map(\.id)))
            let k = PanelInput.rowsChanged(
                from: old, to: new, selection: &viewState.state.selection, held: &held.key, model: model,
                visible: isVisible() && !menu.isOpen)
            guard let k else { return }
            if PanelInput.replaysAfterLayout(k) {
                // Unless the panel was hidden, the menu opened, or the query/results changed in the meantime.
                let (query, mode) = (model.query, model.mode)
                DispatchQueue.main.async {
                    if PanelInput.canReplayDeferred(
                        query: query, mode: mode, answer: new, model: model, visible: isVisible() && !menu.isOpen)
                    {
                        act(k)
                    }
                }
            } else {
                act(k)
            }
        }
        // .repeat: holding ↓/↑ keeps moving (PanelInput ignores other repeats).
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
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
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22); Text(t)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle()).onTapGesture(perform: action)
        // A container (its Text stays findable) whose value says whether ↵ would run it.
        .accessibilityElement(children: .contain)
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        // VoiceOver's press runs it too, as a click does.
        .accessibilityAction(.default, action)
    }

    private func hint(_ t: String, _ k: String) -> some View {
        HStack(spacing: 4) {
            Text(t); Text(k).padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
        }
    }

    /// Re-runs the current query in another mode (the fallback rows).
    private func switchMode(_ m: SearchMode) {
        model.mode = m
        viewState.state.selection = 0
        Task { await model.refresh() }
    }

    /// Routes a key press through ``PanelInput`` and ``PanelState/reduce(_:)``, then performs the effect.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let p = PanelInput.Press(press, event: NSApp.currentEvent)
        // ⌘/, and every key while the FSearch menu is open, go to the menu.
        if let r = menu.handle(p, run: { AppMenuActions.run($0, app: app) }) { return r }
        guard let key = PanelInput.key(for: p, queryIsEmpty: model.query.isEmpty) else {
            return PanelInput.swallows(p) ? .handled : .ignored
        }
        // A result key waits for results that answer the query in the box.
        if let now = PanelInput.gate(key, held: &held.key, model: model) { act(now) }
        return .handled
    }

    private func act(_ key: PanelKey) {
        let shown = self.shown
        let rows = PanelRows(files: shown.count, query: model.query, mode: model.mode)
        viewState.state.query = model.query; viewState.state.mode = model.mode
        viewState.state.count = rows.count; viewState.state.files = shown.count
        let effect = viewState.state.reduce(key)
        // A query change refreshes through .onChange; only a mode change alone needs it here.
        let modeChanged = model.mode != viewState.state.mode
        let queryChanged = model.query != viewState.state.query
        model.query = viewState.state.query; model.mode = viewState.state.mode
        if modeChanged && !queryChanged { Task { await model.refresh() } }
        switch PanelInput.route(effect, rows: rows) {
        case let .perform(e): onEffect(e, shown)
        case let .switchMode(m): switchMode(m)
        case let .runCommand(c): onCommand(c)
        case .ignore: break
        }
    }
}

extension View {
    /// Reports the view's frame in the panel's coordinates (``PanelGeometry``) whenever it changes.
    fileprivate func onPanelFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PanelGeometry.space))
        } action: { frame in
            action(frame)
        }
    }
}

/// What the panel says instead of results. Observes the daemon directly
/// (AppState doesn't forward its changes), so the text changes when the
/// restarts run out.
private struct PhaseMessage: View {
    @Bindable var model: SearchModel
    @ObservedObject var daemon: DaemonManager

    var body: some View {
        if let msg = UserMessage.forPhase(model.phase, helperGaveUp: daemon.isUnresponsive) {
            Text(msg).foregroundStyle(.secondary).padding(16)
        }
    }
}
