import Foundation

/// Makes file names safe to show. A name can hold bidirectional controls
/// (an RLO, U+202E, makes `invoice‮fdp.exe` render as `invoiceexe.pdf`) or other
/// invisible characters that disguise the real extension. Display only: actions
/// always use the original path.
public enum DisplaySafe {
    /// What stands in for a hidden character. U+FFFD is the standard visible
    /// replacement character: every font draws it, it has no bidi behaviour of its
    /// own, and unlike an escape such as `<U+202E>` it keeps the name's length and
    /// layout stable.
    public static let marker: Character = "\u{FFFD}"

    /// `s` with every invisible or reordering scalar replaced by ``marker``.
    ///
    /// Replaced: format characters (general category Cf: the bidi embeddings,
    /// overrides and isolates, LRM/RLM, the Arabic letter mark, zero-width space,
    /// word joiner, BOM, soft hyphen), control characters (Cc) and the line and
    /// paragraph separators. Kept: ZWJ and ZWNJ, which emoji sequences and
    /// Persian and Indic scripts need and which do not reorder text.
    ///
    /// - Parameter s: A file name or folder path.
    /// - Returns: The same text, safe to show.
    public static func name(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if isHidden(scalar) {
                out.append(contentsOf: marker.unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    private static func isHidden(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200C || scalar.value == 0x200D { return false }
        switch scalar.properties.generalCategory {
        case .format, .control, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}
