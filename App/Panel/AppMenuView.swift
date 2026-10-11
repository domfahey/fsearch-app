import FSearchKit
import SwiftUI

/// The footer's gear: opens and closes the FSearch menu, as ⌘/ does.
struct AppMenuButton: View {
    let menu: AppMenuState

    var body: some View {
        Button {
            menu.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                Text("FSearch")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(menu.isOpen ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("FSearch menu ⌘/")
        .accessibilityLabel("FSearch menu")
        .accessibilityIdentifier("appMenuButton")
    }
}

/// The open menu over the panel: a clear layer that closes it on a click outside, and the card above the footer.
struct AppMenuOverlay: View {
    let menu: AppMenuState
    let run: (PanelMenuAction) -> Void

    /// Leaves the footer (and its gear) uncovered, so the card sits just above it.
    static let footerHeight: CGFloat = 36

    var body: some View {
        if menu.isOpen {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { menu.close() }
                    .accessibilityHidden(true)
                AppMenuView(menu: menu, run: run)
                    .padding(.leading, 8).padding(.bottom, Self.footerHeight)
            }
        }
    }
}

/// The FSearch menu card: the version header, the rows (scrolling if tall), and the filter field.
struct AppMenuView: View {
    @Bindable var menu: AppMenuState
    let run: (PanelMenuAction) -> Void
    @FocusState private var fieldFocused: Bool

    static let width: CGFloat = 300
    /// The rows scroll past this height, between the fixed header and field.
    static let maxRowsHeight: CGFloat = 290
    private static let rowHeight: CGFloat = 26, sectionHeight: CGFloat = 24, dividerHeight: CGFloat = 9
    private static let rowsPadding: CGFloat = 4

    /// The height the rows need, so a short menu doesn't stretch to the maximum.
    static func rowsHeight(_ sections: [PanelMenuSection]) -> CGFloat {
        guard !sections.isEmpty else { return 36 }
        let rows = CGFloat(sections.map(\.items.count).reduce(0, +)) * rowHeight
        let headers = CGFloat(sections.filter { $0.title != nil }.count) * sectionHeight
        return rows + headers + CGFloat(sections.count - 1) * dividerHeight + 2 * rowsPadding
    }

    var body: some View {
        let sections = menu.model.visibleSections
        let selected = menu.model.selected?.action
        let v = AppMenuActions.version()
        VStack(alignment: .leading, spacing: 0) {
            Text(PanelMenuModel.header(version: v.version, build: v.build))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                .accessibilityLabel(PanelMenuModel.headerLabel(version: v.version, build: v.build))
                .accessibilityIdentifier("appMenuHeader")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if sections.isEmpty {
                            Text("No matching actions").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .accessibilityIdentifier("appMenuEmpty")
                        }
                        ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                            if i > 0 { Divider().padding(.vertical, 4).padding(.horizontal, 8) }
                            if let title = section.title {
                                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).frame(height: Self.sectionHeight, alignment: .bottom)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(section.items) { item in
                                row(item, selected: item.action == selected).id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, Self.rowsPadding)
                }
                .frame(height: min(Self.rowsHeight(sections), Self.maxRowsHeight))
                .onChange(of: menu.model.selection) {
                    if let id = menu.model.selected?.id { proxy.scrollTo(id) }
                }
            }
            Divider()
            TextField("Search for actions…", text: $menu.model.filter)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($fieldFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .accessibilityLabel("Search for actions")
                .accessibilityIdentifier("appMenuField")
        }
        .frame(width: Self.width)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("FSearch menu")
        .accessibilityIdentifier("appMenu")
        .onAppear { fieldFocused = true }
    }

    private func row(_ item: PanelMenuItem, selected: Bool) -> some View {
        Button {
            menu.choose(item.action, run: run)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(item.title)
                Spacer(minLength: 8)
                if let detail = item.detail { Text(detail).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 3) {
                    ForEach(item.shortcut, id: \.self) { Keycap(symbol: $0) }
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: Self.rowHeight)
            .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { menu.model.select(item.action) } }
        .accessibilityLabel(item.title)
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appMenu-\(item.id)")
    }
}

/// One key of a shortcut badge (⌘, then ,), Raycast-style.
private struct Keycap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 1)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}
