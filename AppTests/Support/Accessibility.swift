import AppKit
import ApplicationServices
import SwiftUI

/// One element of a hosted view's accessibility tree: what VoiceOver reads and presses.
/// SwiftUI's elements implement the NSAccessibility methods without Swift seeing the
/// conformance, so they are read by selector.
@MainActor
struct AXNode {
    let object: NSObject
    private func string(_ key: String) -> String {
        guard object.responds(to: NSSelectorFromString(key)) else { return "" }
        return object.value(forKey: key) as? String ?? ""
    }
    var role: String { string("accessibilityRole") }
    var label: String { string("accessibilityLabel") }
    var title: String { string("accessibilityTitle") }
    var value: String { string("accessibilityValue") }
    var identifier: String { string("accessibilityIdentifier") }
    /// Every readable string on the element.
    var texts: [String] { [label, title, value].filter { !$0.isEmpty } }
    var children: [NSObject] {
        guard object.responds(to: NSSelectorFromString("accessibilityChildren")) else { return [] }
        return object.value(forKey: "accessibilityChildren") as? [NSObject] ?? []
    }
    var isEnabled: Bool {
        guard object.responds(to: NSSelectorFromString("isAccessibilityEnabled")) else { return true }
        return object.value(forKey: "accessibilityEnabled") as? Bool ?? true
    }
    /// Presses it, as VoiceOver would.
    func press() { _ = object.perform(NSSelectorFromString("accessibilityPerformPress")) }
}

/// SwiftUI's hosting views expose no accessibility children until the process
/// has been asked an accessibility question. Setting AXManualAccessibility on our
/// own app element is enough: the call returns at once with
/// kAXErrorAttributeUnsupported (-25205), and afterwards the tree is there. Why
/// is undocumented; `theAccessibilityTreeIsBuilt` fails first if it stops working.
@MainActor
let enableSwiftUIAccessibility: Void = {
    _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
}()

/// The accessibility tree under the window's content, depth first.
@MainActor
func axNodes(in w: NSWindow) -> [AXNode] {
    _ = enableSwiftUIAccessibility
    var out: [AXNode] = []
    func walk(_ o: NSObject, depth: Int) {
        guard depth < 40 else { return }
        let n = AXNode(object: o)
        out.append(n)
        for c in n.children { walk(c, depth: depth + 1) }
    }
    if let v = w.contentView { walk(v, depth: 0) }
    return out
}

/// Every string the window's content reads out.
@MainActor
func axTexts(in w: NSWindow) -> [String] { axNodes(in: w).flatMap(\.texts) }

/// The first element in the window reading `text`.
@MainActor
func axNode(_ text: String, in w: NSWindow) -> AXNode? { axNodes(in: w).first { $0.texts.contains(text) } }

/// Text rendered next to a view under test, so a check that something is absent
/// first proves the tree was built.
let axSentinel = "fsearch-ax-sentinel"

/// Waits (up to 3 s) for an element reading `text`; the tree fills in after the first render.
@MainActor
func axWait(_ text: String, in w: NSWindow) async -> AXNode? {
    _ = await eventually { axNode(text, in: w) != nil }
    return axNode(text, in: w)
}

/// Waits (up to 3 s) for an element with the identifier `id`.
@MainActor
func axWait(id: String, in w: NSWindow) async -> AXNode? {
    _ = await eventually { axNode(id: id, in: w) != nil }
    return axNode(id: id, in: w)
}

/// The first element in the window with the accessibility identifier `id`.
@MainActor
func axNode(id: String, in w: NSWindow) -> AXNode? { axNodes(in: w).first { $0.identifier == id } }
