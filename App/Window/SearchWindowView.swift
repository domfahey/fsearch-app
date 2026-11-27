import AppKit
import FSearchKit
import SwiftUI

/// Bridges SwiftUI `Table` column headers directly onto ``SearchWindowSort`` / ``SearchWindowRow/sort(_:by:)``.
struct SearchWindowComparator: SortComparator, Sendable {
    var column: SearchWindowColumn
    var order: SortOrder = .forward

    init(_ column: SearchWindowColumn, order: SortOrder = .forward) {
        self.column = column
        self.order = order
    }

    func compare(_ lhs: SearchWindowRow, _ rhs: SearchWindowRow) -> ComparisonResult {
        let sorted = SearchWindowRow.sort([lhs, rhs], by: SearchWindowSort(column: column, direction: direction))
        if sorted.first?.id == lhs.id && sorted.last?.id == rhs.id && lhs.id != rhs.id { return .orderedAscending }
        if sorted.first?.id == rhs.id && sorted.last?.id == lhs.id && lhs.id != rhs.id { return .orderedDescending }
        return .orderedSame
    }

    var direction: SortDirection { order == .forward ? .ascending : .descending }

    static func from(_ sort: SearchWindowSort) -> [SearchWindowComparator] {
        [SearchWindowComparator(sort.column, order: sort.direction == .ascending ? .forward : .reverse)]
    }
}

/// Everything-style multi-window desktop search browser: dense sortable table, match toggles,
/// clickable filter chips, saved searches sidebar, keyboard actions, multi-select, drag-out, and Quick Look preview pane.
struct SearchWindowView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityStyleOverride) private var styleOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: SearchWindowModel
    let savedStore: SavedSearchStore
    let onNewWindow: () -> Void
    let onTitleChange: (String) -> Void

    @State private var selection: Set<SearchWindowRow.ID> = []
    @State private var tableSortOrder: [SearchWindowComparator] = SearchWindowComparator.from(.defaultSort)
    @SceneStorage("searchWindowColumns") private var columnCustomization: TableColumnCustomization<SearchWindowRow>
    @State private var showSidebar = true
    @State private var showPreview = true
    @State private var savedSearches: [SavedSearch] = []
    @State private var showSavePopover = false
    @State private var saveName = ""
    @State private var showExtensionPopover = false
    @State private var extensionInput = ""
    @State private var windowError: String?
    @State private var errorClearTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    #if DEBUG
        private let pickFolderOverride: (() -> String?)?
        private let indexingPollInterval: Duration

        init(
            model: SearchWindowModel, savedStore: SavedSearchStore,
            onNewWindow: @escaping () -> Void = {},
            onTitleChange: @escaping (String) -> Void = { _ in },
            selection: Set<SearchWindowRow.ID> = [],
            showSidebar: Bool = true, showPreview: Bool = true,
            windowError: String? = nil,
            pickFolderOverride: (() -> String?)? = nil,
            indexingPollInterval: Duration = .seconds(2)
        ) {
            self.model = model
            self.savedStore = savedStore
            self.onNewWindow = onNewWindow
            self.onTitleChange = onTitleChange
            _selection = State(initialValue: selection)
            _showSidebar = State(initialValue: showSidebar)
            _showPreview = State(initialValue: showPreview)
            _windowError = State(initialValue: windowError)
            self.pickFolderOverride = pickFolderOverride
            self.indexingPollInterval = indexingPollInterval
        }
    #else
        private let indexingPollInterval: Duration = .seconds(2)

        init(
            model: SearchWindowModel, savedStore: SavedSearchStore,
            onNewWindow: @escaping () -> Void = {},
            onTitleChange: @escaping (String) -> Void = { _ in }
        ) {
            self.model = model
            self.savedStore = savedStore
            self.onNewWindow = onNewWindow
            self.onTitleChange = onTitleChange
        }
    #endif

    private struct SearchTrigger: Equatable {
        let query: String
        let mode: SearchMode
        let options: SearchMatchOptions
        let chips: [SearchFilterChip]
    }

    private var selectedRows: [SearchWindowRow] {
        model.rows.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topSearchBar
            Divider()
            filterChipsBar
            Divider()
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar
                    Divider()
                }
                resultsArea
                if showPreview {
                    Divider()
                    SearchPreviewPane(
                        selected: selectedRows,
                        onOpen: openExplicitly,
                        onReveal: revealSelected,
                        onCopyPath: copySelectedPaths
                    )
                }
            }
            Divider()
            statusBar
        }
        .background {
            ZStack {
                keyboardShortcutsLayer
                SearchWindowIndexingObserver(
                    model: model, daemon: app.daemon, pollInterval: indexingPollInterval,
                    onRefreshed: {
                        let valid = Set(model.rows.map(\.id))
                        selection = selection.intersection(valid)
                    })
            }
        }
        .respectingReduceMotion(AccessibilityStyle.resolved(override: styleOverride, reduceMotion: reduceMotion).suppressesAnimations)
        .onAppear {
            savedSearches = savedStore.load()
            tableSortOrder = SearchWindowComparator.from(model.sort)
        }
        .onChange(of: app.savedSearchesGeneration) { _, _ in
            savedSearches = savedStore.load()
        }
        .onChange(of: model.query) { _, newValue in
            onTitleChange(newValue)
        }
        .onChange(of: tableSortOrder) { _, newOrder in
            guard let first = newOrder.first else { return }
            let next = SearchWindowSort(column: first.column, direction: first.direction)
            if model.sort != next { model.sort = next }
        }
        .onChange(of: model.sort) { _, newSort in
            let next = SearchWindowComparator.from(newSort)
            if tableSortOrder != next { tableSortOrder = next }
        }
        .task(id: SearchTrigger(query: model.query, mode: model.mode, options: model.options, chips: model.chips)) {
            if !model.query.isEmpty {
                try? await Task.sleep(for: .milliseconds(60))
                if Task.isCancelled { return }
            }
            if model.query != "" || !model.chips.isEmpty { clearWindowError() }
            await model.refresh()
            let valid = Set(model.rows.map(\.id))
            selection = selection.intersection(valid)
        }
    }

    private var topSearchBar: some View {
        HStack(spacing: 8) {
            Button {
                showSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
            .accessibilityLabel("Toggle Sidebar")
            .accessibilityIdentifier("searchWindowToggleSidebar")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search files, filters, or contents…", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityIdentifier("searchWindowField")
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))

            Picker("Mode", selection: $model.mode) {
                Text("Names").tag(SearchMode.names)
                Text("Inside Files").tag(SearchMode.content)
                Text("Definitions").tag(SearchMode.symbols)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .accessibilityIdentifier("searchWindowModePicker")

            matchToggle(label: "Aa", help: "Match Case", isOn: $model.options.matchCase, id: "toggleMatchCase")
                .disabled(model.mode == .symbols)
            matchToggle(label: "W", help: "Whole Word", isOn: $model.options.wholeWord, id: "toggleWholeWord")
                .disabled(model.mode == .symbols)
            matchToggle(label: ".*", help: "Regular Expression", isOn: $model.options.regex, id: "toggleRegex")
                .disabled(model.mode == .symbols)
            matchToggle(label: "/", help: "Search in Path", isOn: $model.options.searchInPath, id: "toggleSearchInPath")
                .disabled(model.mode != .names)

            Button {
                showPreview.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Toggle Preview Pane")
            .accessibilityLabel("Toggle Preview Pane")
            .accessibilityIdentifier("searchWindowTogglePreview")

            Button(action: onNewWindow) {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .help("New Search Window")
            .accessibilityLabel("New Search Window")
            .accessibilityIdentifier("searchWindowNew")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func matchToggle(label: String, help: String, isOn: Binding<Bool>, id: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(verbatim: label)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(minWidth: 24, minHeight: 20)
        }
        .buttonStyle(.bordered)
        .tint(isOn.wrappedValue ? .accentColor : nil)
        .help(LocalizedStringKey(help))
        .accessibilityLabel(LocalizedStringKey(help))
        .accessibilityValue(isOn.wrappedValue ? Text("On") : Text("Off"))
        .accessibilityIdentifier(id)
    }

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chipMenu("Type", presets: SearchFilterChip.typePresets)
                chipMenu("Kind", presets: SearchFilterChip.kindPresets)
                chipMenu("Size", presets: SearchFilterChip.sizePresets)
                chipMenu("Modified", presets: SearchFilterChip.modifiedPresets)

                Menu("Folder") {
                    ForEach(SearchFilterChip.folderPresets) { chip in
                        Button(chip.title) { model.toggleChip(chip) }
                    }
                    Divider()
                    Button("Choose Folder…", action: chooseFolder)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button("Extension…") {
                    extensionInput = ""
                    showExtensionPopover = true
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("searchWindowExtensionButton")
                .popover(isPresented: $showExtensionPopover) {
                    SearchWindowInputPopover(
                        heading: "Filter by extension",
                        placeholder: "swift, md, pdf",
                        actionTitle: "Add",
                        text: $extensionInput,
                        onSubmit: applyExtensionInput
                    )
                }

                if !model.chips.isEmpty {
                    Divider().frame(height: 14)
                    ForEach(model.chips) { chip in
                        HStack(spacing: 4) {
                            Text(verbatim: chip.title)
                                .font(.caption)
                            Button {
                                model.removeChip(id: chip.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(chip.title)")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .accessibilityIdentifier("chip-\(chip.id)")
                    }
                }

                if !model.chips.isEmpty || model.options.hasAnyOption {
                    Button("Clear Filters") {
                        model.clearFilters()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("searchWindowClearFilters")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func chipMenu(_ title: LocalizedStringKey, presets: [SearchFilterChip]) -> some View {
        Menu(title) {
            ForEach(presets) { chip in
                Button(chip.title) { model.toggleChip(chip) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Filters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(SavedSearch.builtInPresets) { preset in
                        Button {
                            applySavedSearch(preset)
                        } label: {
                            Label(preset.name, systemImage: preset.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Searches")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if savedSearches.isEmpty {
                        Text("No saved searches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(savedSearches) { saved in
                            HStack(spacing: 4) {
                                Button {
                                    applySavedSearch(saved)
                                } label: {
                                    Label(saved.name, systemImage: saved.symbol)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    savedSearches = savedStore.delete(id: saved.id)
                                    app.savedSearchesChanged()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(saved.name)")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Button {
                        saveName = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
                        showSavePopover = true
                    } label: {
                        Label("Save Current Search…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 4)
                    .accessibilityIdentifier("searchWindowSaveButton")
                    .popover(isPresented: $showSavePopover) {
                        SearchWindowInputPopover(
                            heading: "Save Search",
                            placeholder: "Name",
                            actionTitle: "Save",
                            text: $saveName,
                            onSubmit: saveCurrentSearch
                        )
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 195)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .accessibilityIdentifier("searchWindowSidebar")
    }

    private var resultsArea: some View {
        ZStack {
            Table(model.rows, selection: $selection, sortOrder: $tableSortOrder, columnCustomization: $columnCustomization) {
                TableColumn("Name", sortUsing: SearchWindowComparator(.name)) { row in
                    SearchWindowNameCell(row: row)
                }
                .width(min: 160, ideal: 250)
                .customizationID("name")

                TableColumn("Folder", sortUsing: SearchWindowComparator(.folder)) { row in
                    Text(verbatim: row.folder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 120, ideal: 220)
                .customizationID("folder")

                TableColumn("Size", sortUsing: SearchWindowComparator(.size)) { row in
                    Text(verbatim: row.sizeFormatted)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 65, ideal: 80)
                .customizationID("size")

                TableColumn("Kind", sortUsing: SearchWindowComparator(.kind)) { row in
                    Text(verbatim: row.kindLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 60, ideal: 90)
                .customizationID("kind")

                TableColumn("Date Modified", sortUsing: SearchWindowComparator(.modified)) { row in
                    Text(verbatim: row.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 150)
                .customizationID("modified")
            }
            .contextMenu(forSelectionType: SearchWindowRow.ID.self) { ids in
                SearchWindowContextMenu(
                    rows: rowsForAction(ids: ids),
                    app: app,
                    onError: showWindowError,
                    refresh: { await model.refresh() }
                )
            } primaryAction: { ids in
                SearchWindowActions.openSelected(rowsForAction(ids: ids), app: app, onError: showWindowError)
            }
            .accessibilityIdentifier("searchWindowTable")

            if model.rows.isEmpty {
                emptyResultsOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyResultsOverlay: some View {
        VStack(spacing: 8) {
            switch model.phase {
            case .idle:
                Text("Type a query or choose a filter to search your Mac")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text("Searching…")
                    .foregroundStyle(.secondary)
            case .results:
                Text("No matching files")
                    .foregroundStyle(.secondary)
            case .indexing:
                ProgressView()
                    .controlSize(.small)
                Text("Indexing your disk… results will appear shortly")
                    .foregroundStyle(.secondary)
            case let .failed(error):
                Text(verbatim: UserMessage.forPhase(.failed(error), helperGaveUp: app.daemon.isUnresponsive) ?? error.description)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("searchWindowEmptyOverlay")
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(verbatim: SearchWindowStatus.resultSummary(count: model.rows.count, hitCap: model.hitCap))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("searchWindowResultCount")

            if let selSummary = SearchWindowStatus.selectionSummary(selected: selectedRows) {
                Text(verbatim: "· \(selSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("searchWindowSelectionSummary")
            }

            if let windowError {
                Text(verbatim: windowError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .accessibilityIdentifier("searchWindowError")
            }

            Spacer(minLength: 8)

            if let tookUs = model.lastTookUs {
                Text(verbatim: DebugFormat.daemonMs(tookUs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("searchWindowTiming")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Row-level shortcuts (`↵`, `⌘↵`, `⌘⇧C`, `⌘Y`, `⌘⌫`) stay disabled while editing text or popovers,
    /// so `⌘⌫` never trashes a selected file while deleting query text and `↵` never interferes with IME or popovers.
    static func rowShortcutsEnabled(searchFocused: Bool, popoverOpen: Bool, hasSelection: Bool) -> Bool {
        !searchFocused && !popoverOpen && hasSelection
    }

    private var keyboardShortcutsLayer: some View {
        let rowEnabled = Self.rowShortcutsEnabled(
            searchFocused: searchFocused,
            popoverOpen: showSavePopover || showExtensionPopover,
            hasSelection: !selectedRows.isEmpty)
        return Group {
            Button("New Window", action: onNewWindow).keyboardShortcut("n", modifiers: .command)
            Button("Focus Search") { searchFocused = true }.keyboardShortcut("l", modifiers: .command)
            Button("Toggle Preview") { showPreview.toggle() }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Open Selected", action: openSelected).keyboardShortcut(.return, modifiers: []).disabled(!rowEnabled)
            Button("Reveal Selected", action: revealSelected).keyboardShortcut(.return, modifiers: .command).disabled(!rowEnabled)
            Button("Copy Files", action: copySelectedFiles).keyboardShortcut("c", modifiers: [.command, .shift]).disabled(!rowEnabled)
            Button("Quick Look", action: toggleQuickLook).keyboardShortcut("y", modifiers: .command).disabled(!rowEnabled)
            Button("Trash Selected", action: trashSelected).keyboardShortcut(.delete, modifiers: .command).disabled(!rowEnabled)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    func rowsForAction(ids: Set<SearchWindowRow.ID>) -> [SearchWindowRow] {
        let effective = ids.isEmpty ? selection : ids
        return model.rows.filter { effective.contains($0.id) }
    }

    private func applySavedSearch(_ saved: SavedSearch) {
        model.apply(saved)
        onTitleChange(model.query)
    }

    private func saveCurrentSearch() {
        savedSearches = savedStore.add(model.snapshot(name: saveName))
        app.savedSearchesChanged()
        showSavePopover = false
    }

    private func applyExtensionInput() {
        if let chip = SearchFilterChip.extensionChip(extensionInput) {
            model.addChip(chip)
        }
        showExtensionPopover = false
    }

    private func chooseFolder() {
        let picked = Self.pickFolder(
            override: {
                #if DEBUG
                    pickFolderOverride
                #else
                    nil
                #endif
            }())
        if let picked, let chip = SearchFilterChip.folderChip(picked) {
            model.addChip(chip)
        }
    }

    static func pickFolder(override: (() -> String?)? = nil, inert: Bool = Presentation.inert) -> String? {
        if let override { return override() }
        guard !inert else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func openSelected() { SearchWindowActions.openSelected(selectedRows, app: app, onError: showWindowError) }
    private func openExplicitly() {
        SearchWindowActions.openSelected(selectedRows, app: app, respectLaunchableReveal: false, onError: showWindowError)
    }
    private func revealSelected() { SearchWindowActions.revealSelected(selectedRows, onError: showWindowError) }
    private func copySelectedPaths() { SearchWindowActions.copyPaths(selectedRows) }
    private func copySelectedFiles() { SearchWindowActions.copyFiles(selectedRows, onError: showWindowError) }
    private func toggleQuickLook() { SearchWindowActions.toggleQuickLook(selectedRows, onError: showWindowError) }
    private func trashSelected() {
        Task { await SearchWindowActions.trashSelected(selectedRows, app: app, onError: showWindowError) { await model.refresh() } }
    }
    private func showWindowError(_ message: String) {
        windowError = message
        errorClearTask?.cancel()
        let duration = app.actionErrorDuration
        errorClearTask = Task {
            try? await Task.sleep(for: duration)
            if !Task.isCancelled { windowError = nil }
        }
    }

    private func clearWindowError() {
        errorClearTask?.cancel()
        errorClearTask = nil
        windowError = nil
    }
}

/// Name cell for a search window table row, showing the file icon, display-safe name, optional matching line, and drag support.
struct SearchWindowNameCell: View {
    let row: SearchWindowRow

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(for: row.path, isDirectory: row.isDirectory))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.name).lineLimit(1)
                if let line = row.lineNumber, let match = row.matchText {
                    Text(verbatim: "\(line) · \(match)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .draggable(FileActions.url(row.path))
    }
}

/// Compact text-input popover shared by **Filter by extension** and **Save Search**.
struct SearchWindowInputPopover: View {
    let heading: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.headline)
            TextField(placeholder, text: $text)
                .frame(width: 190)
                .onSubmit(onSubmit)
            HStack {
                Spacer()
                Button(actionTitle, action: onSubmit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

/// Context menu items for selected rows in the search window table.
struct SearchWindowContextMenu: View {
    let rows: [SearchWindowRow]
    let app: AppState
    let onError: @MainActor (String) -> Void
    let refresh: @MainActor () async -> Void

    var body: some View {
        Button("Open") { SearchWindowActions.openSelected(rows, app: app, respectLaunchableReveal: false, onError: onError) }
        Button("Reveal in Finder") { SearchWindowActions.revealSelected(rows, onError: onError) }
        Button("Quick Look") { SearchWindowActions.toggleQuickLook(rows, onError: onError) }
        Divider()
        Button("Copy Path") { SearchWindowActions.copyPaths(rows) }
        Button("Copy File") { SearchWindowActions.copyFiles(rows, onError: onError) }
        Button("Open Folder in Terminal") { SearchWindowActions.openTerminal(rows, onError: onError) }
        Divider()
        Button("Move to Trash", role: .destructive) {
            Task { await SearchWindowActions.trashSelected(rows, app: app, onError: onError, refresh: refresh) }
        }
    }
}

/// Polls while a search window is visible and either the model or daemon reports `.indexing`,
/// re-running the window's query once indexing completes without requiring another edit.
private struct SearchWindowIndexingObserver: View {
    @Bindable var model: SearchWindowModel
    @ObservedObject var daemon: DaemonManager
    let pollInterval: Duration
    let onRefreshed: () -> Void
    @State private var host = HostWindow()
    @State private var shown = 0

    private var isIndexing: Bool {
        if daemon.state == .indexing { return true }
        switch model.phase {
        case .indexing, .failed(.indexing): return true
        default: return false
        }
    }

    private struct PollKey: Equatable {
        let indexing: Bool
        let shown: Int
    }

    var body: some View {
        HostWindowReader(host: host)
            .frame(width: 0, height: 0)
            .task(id: PollKey(indexing: isIndexing, shown: shown)) {
                let host = host
                let interval = pollInterval
                await DaemonMessageLine.pollWhileIndexing(
                    isIndexing: { isIndexing },
                    visible: { host.window?.isVisible == true },
                    sleep: { try await Task.sleep(for: interval) },
                    step: {
                        await daemon.refresh()
                        // Run refresh in an uncancelled task so flipping from `.indexing` -> `.running` + `.loading`
                        // doesn't cancel the final fetch mid-flight once indexing finishes.
                        let refreshTask = Task { @MainActor in
                            await model.refresh()
                            onRefreshed()
                        }
                        await refreshTask.value
                    })
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
                guard let w = note.object as? NSWindow, w === host.window, w.occlusionState.contains(.visible) else { return }
                shown &+= 1
            }
    }
}
