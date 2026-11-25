import FSearchKit
import SwiftUI

/// One result: the file's icon and name with its folder (or the matching line), the first query word highlighted.
struct ResultRow: View {
    /// The result shown.
    let item: ResultItem
    /// The text to highlight (in the filename for file hits, or in the matching line for content/definition hits).
    let query: String
    /// Whether the row is the selected one.
    let selected: Bool
    /// Invoked when VoiceOver activates the row.
    var onActivate: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: item.path, isDirectory: Self.isDirectory(item)))
                .resizable().frame(width: 22, height: 22)
            Text(Self.nameText(for: item, query: query)).lineLimit(1).layoutPriority(1)
            Text(Self.detailText(for: item, query: query)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        // Container keeps child Text nodes findable while exposing selection and a combined label to VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityValue(selected ? "selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(.default) { onActivate?() }
        .accessibilityIdentifier("result-\(item.id)")
    }

    /// A name result the daemon says is a folder (kind "dir"); content hits are files.
    static func isDirectory(_ item: ResultItem) -> Bool {
        if case let .file(h) = item { return h.kind == "dir" }
        return false
    }

    /// Highlights the filename only for file-name hits; content/definition rows highlight the matching line instead.
    static func nameText(for item: ResultItem, query: String) -> AttributedString {
        let name = (item.path as NSString).lastPathComponent
        if case .file = item { return highlighted(name, query) }
        return AttributedString(name)
    }

    /// Shows the folder path for file hits, or `<line> · <highlighted match>` for content/definition hits.
    static func detailText(for item: ResultItem, query: String) -> AttributedString {
        switch item {
        case .file:
            return AttributedString(((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
        case let .line(_, m):
            var out = AttributedString("\(m.line) · ")
            out.append(highlighted(m.text.trimmingCharacters(in: .whitespaces), query))
            return out
        }
    }

    private var name: String { (item.path as NSString).lastPathComponent }

    private var detail: String {
        switch item {
        case .file: ((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        case let .line(_, m): "\(m.line) · \(m.text.trimmingCharacters(in: .whitespaces))"
        }
    }

    /// `s` with the first word of `q` marked, ignoring case.
    static func highlighted(_ s: String, _ q: String) -> AttributedString {
        var a = AttributedString(s)
        let word = q.split(separator: " ").first.map(String.init) ?? ""
        if !word.isEmpty, let r = a.range(of: word, options: .caseInsensitive) {
            a[r].backgroundColor = .yellow.opacity(0.45)
        }
        return a
    }
}
