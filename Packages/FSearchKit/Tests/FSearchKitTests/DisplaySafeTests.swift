import Foundation
import Testing

@testable import FSearchKit

@Suite struct DisplaySafeTests {
    /// The classic spoof: an RLO makes "invoice\u{202E}fdp.exe" render as "invoiceexe.pdf".
    @Test func replacesBidiOverrides() {
        #expect(DisplaySafe.name("invoice\u{202E}fdp.exe") == "invoice\u{FFFD}fdp.exe")
    }

    @Test func replacesEveryBidiAndInvisibleControl() {
        let bad: [UInt32] = [
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F, 0x061C, 0x200B, 0x2060, 0xFEFF,
            0x00AD, 0x0007, 0x000A, 0x2028,
        ]
        for v in bad {
            let s = "a" + String(Unicode.Scalar(v)!) + "b"
            #expect(DisplaySafe.name(s) == "a\u{FFFD}b", "U+\(String(v, radix: 16))")
        }
    }

    @Test func leavesOrdinaryTextAlone() {
        for s in ["report.pdf", "日本語.txt", "עברית.txt", "🏡 notes.md", "👨\u{200D}👩\u{200D}👧.png", "فارسی\u{200C}نامه.txt", "e\u{301}.txt"] {
            #expect(DisplaySafe.name(s) == s)
        }
    }
}
