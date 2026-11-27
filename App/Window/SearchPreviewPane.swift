import AppKit
import FSearchKit
import Quartz
import SwiftUI

/// Toggleable right-hand preview pane for the search window: file metadata, content-match line highlight, and Quick Look.
struct SearchPreviewPane: View {
    @Environment(\.accessibilityStyleOverride) private var styleOverride
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Currently selected table rows (zero, one, or many).
    let selected: [SearchWindowRow]
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onCopyPath: () -> Void

    private var a11y: AccessibilityStyle {
        AccessibilityStyle.resolved(override: styleOverride, reduceTransparency: reduceTransparency, contrast: colorSchemeContrast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selected.isEmpty {
                emptyState
            } else if selected.count == 1, let row = selected.first {
                singleSelection(row)
            } else {
                multiSelection
            }
        }
        .padding(14)
        .frame(minWidth: 250, idealWidth: 290, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(a11y.usesOpaqueSurface ? 1 : 0.45))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("searchWindowPreviewPane")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Select a file to preview")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func singleSelection(_ row: SearchWindowRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: IconCache.shared.icon(for: row.path, isDirectory: row.isDirectory))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(verbatim: row.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let line = row.lineNumber, let matchText = row.matchText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Line \(line)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: matchText)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(a11y.increasedContrast ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(a11y.chipStrokeOpacity > 0 ? Color.primary.opacity(a11y.chipStrokeOpacity) : .clear)
                        )
                }
            }

            QuickLookPreviewRepresentable(url: FileActions.url(row.path))
                .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(a11y.increasedContrast ? a11y.surfaceStrokeOpacity : 0.16))
                )

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Folder").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: row.folder).font(.caption).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                GridRow {
                    Text("Size").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: row.sizeFormatted).font(.caption.monospacedDigit())
                }
                GridRow {
                    Text("Modified").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: row.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "–").font(.caption)
                }
            }

            HStack(spacing: 8) {
                Button("Open", action: onOpen)
                Button("Reveal", action: onReveal)
                Button("Copy Path", action: onCopyPath)
            }
            .controlSize(.small)
        }
    }

    private var multiSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: SearchWindowStatus.selectionSummary(selected: selected) ?? "")
                        .font(.headline)
                    Text("Multiple items selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Open", action: onOpen)
                Button("Reveal", action: onReveal)
                Button("Copy Path", action: onCopyPath)
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hosts `Quartz.QLPreviewView` for live file previews; stays an inert placeholder in unit tests so Quick Look plugins never load.
struct QuickLookPreviewRepresentable: NSViewRepresentable {
    let url: URL
    var inert: Bool = Presentation.inert

    func makeNSView(context: Context) -> NSView {
        guard !inert else { return NSView() }
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.shouldCloseWithWindow = false
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !inert, let preview = nsView as? QLPreviewView else { return }
        if (preview.previewItem as? URL) != url {
            preview.previewItem = url as NSURL
        }
    }

    /// Explicitly closes `QLPreviewView` when unmounted (pane hidden or selection changed) so XPC preview resources
    /// and auto-started audio/video playback are released immediately.
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let preview = nsView as? QLPreviewView else { return }
        preview.previewItem = nil
        preview.close()
    }
}
