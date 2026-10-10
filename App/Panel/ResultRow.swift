import FSearchKit
import SwiftUI

/// One result: the file's icon and name with its folder (or the matching line), the first query word highlighted.
struct ResultRow: View {
    /// The result shown.
    let item: ResultItem
    /// The text to highlight in the name.
    let query: String
    /// Whether the row is the selected one.
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: item.path)).resizable().frame(width: 22, height: 22)
            Text(highlighted(name, query)).lineLimit(1).layoutPriority(1)
            Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var name: String { (item.path as NSString).lastPathComponent }

    private var detail: String {
        switch item {
        case .file: ((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        case let .line(_, m): "\(m.line) · \(m.text.trimmingCharacters(in: .whitespaces))"
        }
    }

    /// `s` with the first word of `q` marked, ignoring case.
    private func highlighted(_ s: String, _ q: String) -> AttributedString {
        var a = AttributedString(s)
        let word = q.split(separator: " ").first.map(String.init) ?? ""
        if !word.isEmpty, let r = a.range(of: word, options: .caseInsensitive) {
            a[r].backgroundColor = .yellow.opacity(0.45)
        }
        return a
    }
}
