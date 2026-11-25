import AppKit
import FSearchKit
import Foundation
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct AccessibilityTests {
        @Test func menuBarLabelReflectsWarningAndUpdateState() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            let status = MenuBarStatus(defaults: env.defaults)
            _ = status.icon(for: env.app)
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning != nil })

            let w = await render(MenuBarLabel(app: env.app, status: status))
            defer { w.close() }
            let expected = "FSearch: \(status.warning?.message ?? "")"
            #expect(await axWait(expected, in: w) != nil, "menu bar icon must announce active warnings")
        }

        @Test func onboardingExposesPrimaryButtonHeaderAndWarningLabel() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .welcome)
            let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
            defer { w.close() }
            let primary = try #require(await axWait(id: "onboardingPrimaryButton", in: w))
            #expect(primary.title == "Continue" || primary.label == "Continue")
            let heading = try #require(axNode("Find anything on your Mac", in: w))
            #expect(heading.role == NSAccessibility.Role.staticText.rawValue || heading.role == "AXHeading")
            #expect(axNodes(in: w).contains { $0.identifier == "onboardingHeading" })
        }

        @Test func settingsWarningHasAccessibleLabelWithoutRawEmojiPrefix() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let u = Uninstaller(
                helper: nil, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: URL(fileURLWithPath: "/fake/data"), logFolder: URL(fileURLWithPath: "/fake/logs"),
                exists: { _ in false }, cliAgentInstalled: { false }, resetShortcut: {})
            let view = SettingsView(
                loginItem: LoginItemModel(service: nil), uninstaller: u,
                runningBundleIds: { ["com.raycast.macos"] }
            ).environmentObject(env.app)
            let w = await render(view, size: NSSize(width: 440, height: 600))
            defer { w.close() }
            #expect(
                await eventually {
                    axNodes(in: w).contains { $0.texts.contains { $0.hasPrefix("Warning:") && $0.contains("Raycast") } }
                })
        }

        @Test func searchLogFilterFieldHasAccessibleLabelAndIdentifier() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let w = await render(SearchLogView().environmentObject(env.app), size: NSSize(width: 760, height: 420))
            defer { w.close() }
            let field = try #require(await axWait(id: "searchLogFilter", in: w))
            #expect(field.texts.contains("Filter search log"))
        }

        @Test func searchViewAnnouncesSearchModeAndDebugIndicator() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            env.app.search.mode = .content
            let held = HeldKeyBox()
            let view = SearchView(
                model: env.app.search, state: PanelState(), held: held, keys: PanelKeyFeed(), geometry: PanelGeometry(),
                menu: AppMenuState(held: held), isVisible: { true },
                onEffect: { _, _ in }, onSelect: { _ in }, onCommand: { _ in }
            ).environmentObject(env.app)
            let w = await render(view)
            defer { w.close() }
            let chip = try #require(await axWait(id: "searchModeChip", in: w))
            #expect(chip.texts.contains("Search mode: Inside files"))
            #expect(chip.help == "Press Backspace in an empty search field to clear")
            let debugDot = try #require(await axWait(id: "debugModeIndicator", in: w))
            #expect(debugDot.texts.contains("Debug mode active"))
        }

        @Test func accessibilityStyleAdaptsToSystemPreferences() {
            let standard = AccessibilityStyle(reduceMotion: false, reduceTransparency: false, contrast: .standard)
            #expect(!standard.usesOpaqueSurface)
            #expect(!standard.suppressesAnimations)
            #expect(standard.selectionStrokeOpacity == 0)
            #expect(standard.chipStrokeOpacity == 0)
            #expect(!standard.underlinesMatch)
            #expect(standard.selectionFillOpacity == 0.08)
            #expect(standard.surfaceStrokeOpacity == 0.12)
            #expect(standard.chipFillOpacity == 0.07)
            #expect(standard.keycapFillOpacity == 0.08)
            #expect(standard.hintStrokeOpacity == 0.5)
            #expect(standard.highlightOpacity == 0.45)

            let adapted = AccessibilityStyle(reduceMotion: true, reduceTransparency: true, contrast: .increased)
            #expect(adapted.usesOpaqueSurface)
            #expect(adapted.suppressesAnimations)
            #expect(adapted.selectionFillOpacity > standard.selectionFillOpacity)
            #expect(adapted.selectionStrokeOpacity > 0)
            #expect(adapted.surfaceStrokeOpacity > standard.surfaceStrokeOpacity)
            #expect(adapted.chipFillOpacity > standard.chipFillOpacity)
            #expect(adapted.chipStrokeOpacity > 0)
            #expect(adapted.keycapFillOpacity > standard.keycapFillOpacity)
            #expect(adapted.hintStrokeOpacity > standard.hintStrokeOpacity)
            #expect(adapted.highlightOpacity > standard.highlightOpacity)
            #expect(adapted.underlinesMatch)
        }

        @Test func menuBarAccessibilityLabelCoversAllStates() {
            #expect(MenuBarStatus.accessibilityLabel(warning: nil, updateAvailable: false) == "FSearch")
            #expect(MenuBarStatus.accessibilityLabel(warning: nil, updateAvailable: true) == "FSearch: Update available")
            let w = MenuBarWarning.evaluate(.failed, skippedFullDiskAccess: false, dismissedReminder: false)
            #expect(MenuBarStatus.accessibilityLabel(warning: w, updateAvailable: true) == "FSearch: \(w?.message ?? "")")
        }

        @Test func resultRowHighlightAddsUnderlineUnderIncreasedContrast() throws {
            let standard = ResultRow.highlighted("heron.txt", "her", increasedContrast: false)
            let stdRange = try #require(standard.range(of: "her"))
            #expect(standard[stdRange].backgroundColor != nil)
            #expect(standard[stdRange].underlineStyle == nil)

            let increased = ResultRow.highlighted("heron.txt", "her", increasedContrast: true)
            let incRange = try #require(increased.range(of: "her"))
            #expect(increased[incRange].backgroundColor != nil)
            #expect(increased[incRange].underlineStyle == .single)
        }

        @Test func highContrastAndOpaqueSurfaceRenderAcrossPanelAndMenu() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            env.app.search.mode = .content
            let held = HeldKeyBox()
            let menu = AppMenuState(held: held)
            menu.toggle()
            let panel = SearchView(
                model: env.app.search, state: PanelState(), held: held, keys: PanelKeyFeed(), geometry: PanelGeometry(),
                menu: menu, isVisible: { true },
                onEffect: { _, _ in }, onSelect: { _ in }, onCommand: { _ in }
            )
            .environmentObject(env.app)
            .environment(
                \.accessibilityStyleOverride,
                AccessibilityStyle(reduceMotion: true, reduceTransparency: true, increasedContrast: true))
            let w = await render(panel)
            defer { w.close() }
            #expect(await axWait(id: "appMenu", in: w) != nil)
            #expect(await axWait(id: "searchModeChip", in: w) != nil)
        }
    }
}
