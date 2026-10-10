import FSearchKit
import SwiftUI

struct ResultRow: View {
    let item: ResultItem
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(for: item.path, isDirectory: Self.isDirectory(item)))
                .resizable().frame(width: 22, height: 22)
            Text(highlighted(name, query)).lineLimit(1).layoutPriority(1)
            Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    /// A name result the daemon says is a folder (kind "dir"); content hits are files.
    static func isDirectory(_ item: ResultItem) -> Bool {
        if case let .file(h) = item { return h.kind == "dir" }
        return false
    }

    private var name: String { (item.path as NSString).lastPathComponent }

    private var detail: String {
        switch item {
        case .file: ((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        case let .line(_, m): "\(m.line) · \(m.text.trimmingCharacters(in: .whitespaces))"
        }
    }

    private func highlighted(_ s: String, _ q: String) -> AttributedString {
        var a = AttributedString(s)
        let word = q.split(separator: " ").first.map(String.init) ?? ""
        if !word.isEmpty, let r = a.range(of: word, options: .caseInsensitive) {
            a[r].backgroundColor = .yellow.opacity(0.45)
        }
        return a
    }
}
