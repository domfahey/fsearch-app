import AppKit
import SwiftUI

/// Visual tokens adapted to macOS Reduce Motion, Reduce Transparency, and Increase Contrast settings.
struct AccessibilityStyle: Equatable, Sendable {
    /// True when the user enabled Reduce Motion.
    let reduceMotion: Bool
    /// True when the user enabled Reduce Transparency.
    let reduceTransparency: Bool
    /// True when the user enabled Increase Contrast.
    let increasedContrast: Bool

    init(reduceMotion: Bool = false, reduceTransparency: Bool = false, increasedContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increasedContrast = increasedContrast
    }

    init(reduceMotion: Bool = false, reduceTransparency: Bool = false, contrast: ColorSchemeContrast) {
        self.init(
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased)
    }

    /// Floating panel and menu cards switch from translucent material to an opaque window background.
    var usesOpaqueSurface: Bool { reduceTransparency }
    /// Implicit SwiftUI animations are suppressed when Reduce Motion is active.
    var suppressesAnimations: Bool { reduceMotion }
    /// Fill opacity for selected rows and active toolbar pills.
    var selectionFillOpacity: Double { increasedContrast ? 0.18 : 0.08 }
    /// Border opacity for selected rows; 0 under standard contrast.
    var selectionStrokeOpacity: Double { increasedContrast ? 0.45 : 0 }
    /// Outer border opacity for floating panel and menu cards.
    var surfaceStrokeOpacity: Double { increasedContrast ? 0.45 : 0.12 }
    /// Fill opacity for search-mode chips ("Inside files", "Definitions").
    var chipFillOpacity: Double { increasedContrast ? 0.16 : 0.07 }
    /// Border opacity for search-mode chips; 0 under standard contrast.
    var chipStrokeOpacity: Double { increasedContrast ? 0.45 : 0 }
    /// Fill opacity for shortcut keycaps in the FSearch menu.
    var keycapFillOpacity: Double { increasedContrast ? 0.18 : 0.08 }
    /// Border opacity for footer shortcut hint badges.
    var hintStrokeOpacity: Double { increasedContrast ? 0.85 : 0.5 }
    /// Background opacity for matched query substrings in result rows.
    var highlightOpacity: Double { increasedContrast ? 0.75 : 0.45 }
    /// Adds an underline alongside the yellow highlight under Increase Contrast.
    var underlinesMatch: Bool { increasedContrast }

    /// Returns `override` when supplied by tests/previews, otherwise reads the live macOS accessibility environment.
    static func resolved(
        override: AccessibilityStyle?, reduceMotion: Bool = false, reduceTransparency: Bool = false,
        contrast: ColorSchemeContrast = .standard
    ) -> AccessibilityStyle {
        override ?? AccessibilityStyle(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency, contrast: contrast)
    }
}

extension EnvironmentValues {
    /// Optional override for tests and previews (SwiftUI's system accessibility environment keys are read-only).
    @Entry var accessibilityStyleOverride: AccessibilityStyle? = nil
}

extension View {
    /// Suppresses implicit animations when macOS Reduce Motion is enabled.
    func respectingReduceMotion(_ reduceMotion: Bool) -> some View {
        transaction { if reduceMotion { $0.animation = nil } }
    }

    /// Background and border for floating surfaces (launcher panel and FSearch menu), respecting Reduce Transparency and Increase Contrast.
    @ViewBuilder
    func panelSurface(cornerRadius: CGFloat, material: Material, style: AccessibilityStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        if style.usesOpaqueSurface {
            self
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(style.surfaceStrokeOpacity)))
        } else {
            self
                .background(material, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(style.surfaceStrokeOpacity)))
        }
    }

    /// Selection background (and outline under Increase Contrast) for rows and active controls.
    func selectionHighlight(selected: Bool, cornerRadius: CGFloat, style: AccessibilityStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return
            self
            .background(selected ? Color.primary.opacity(style.selectionFillOpacity) : .clear, in: shape)
            .overlay(
                shape.stroke(selected && style.selectionStrokeOpacity > 0 ? Color.primary.opacity(style.selectionStrokeOpacity) : .clear)
            )
    }
}
