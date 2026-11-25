import AppKit
import FSearchKit
import Foundation
import Quartz
import Testing

@testable import FSearch

extension AppTests {
    /// The launcher window's own AppKit overrides: losing key, handing Quick
    /// Look over and back, and opening Settings outside the inert host.
    @Suite @MainActor
    struct PanelWindowTests {
        /// The shared controller, shown for `env`; the overrides below talk to it.
        func showShared(_ env: TestEnv) throws -> PanelController.Panel {
            PanelController.shared.show(app: env.app)
            return try #require(PanelController.shared.panel)
        }

        /// Clicking another app takes key from the launcher: it hides.
        @Test func losingKeyHidesTheLauncher() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            #expect(PanelController.shared.isVisible)
            #expect(!QuickLookSource.shared.isPreviewing)
            p.resignKey()
            #expect(!PanelController.shared.isVisible)
        }

        /// Switching to another app hides the launcher even if resignKey did not (e.g. while Quick Look was up).
        @Test func resigningAppActiveHidesTheLauncher() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            _ = try showShared(env)
            #expect(PanelController.shared.isVisible)
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            #expect(!PanelController.shared.isVisible)
        }

        /// The launcher hands the preview its data source and takes it back when the preview closes.
        @Test func quickLookControlIsHandedOverAndBack() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            let ql = try #require(QLPreviewPanel.shared())
            defer { QuickLookSource.shared.detach(ql) }
            #expect(p.acceptsPreviewPanelControl(ql))
            p.beginPreviewPanelControl(ql)
            #expect(ql.dataSource === QuickLookSource.shared)
            // Taking control twice keeps one data source (and one key monitor).
            p.beginPreviewPanelControl(ql)
            #expect(ql.dataSource === QuickLookSource.shared)
            #expect(!ql.isVisible, "the inert host never shows the preview")
            p.endPreviewPanelControl(ql)
            #expect(ql.dataSource == nil)
            // Hide before draining the async focus hand-back queued by endPreviewPanelControl, so it cannot race the next test.
            PanelController.shared.hide(returnFocus: false)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            #expect(!PanelController.shared.isVisible)
        }

        /// The preview closing while FSearch isn't the active app puts the launcher away
        /// (it would otherwise float without the keyboard). Runs only while the test
        /// host is inactive, which is the usual case; the active branch needs a key panel.
        @Test(.enabled("needs the test host inactive") { await MainActor.run { !NSApp.isActive } })
        func previewClosingWhileInactiveHidesTheLauncher() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let p = try showShared(env)
            let ql = try #require(QLPreviewPanel.shared())
            p.beginPreviewPanelControl(ql)
            p.endPreviewPanelControl(ql)
            #expect(await eventually { !PanelController.shared.isVisible })
        }

        /// The data source shows the chosen file, and nothing before one is chosen.
        @Test func theDataSourceServesTheChosenFile() throws {
            let source = QuickLookSource()
            let ql = try #require(QLPreviewPanel.shared())
            #expect(source.numberOfPreviewItems(in: ql) == 0)
            let url = URL(fileURLWithPath: "/p/heron.txt")
            source.toggle(url, inert: true)
            #expect(source.numberOfPreviewItems(in: ql) == 1)
            #expect((source.previewPanel(ql, previewItemAt: 0) as? URL) == url)
            #expect(!ql.isVisible)
            #expect(QuickLookSource.shouldHandle(.close, isRepeat: false))
            #expect(!QuickLookSource.shouldHandle(.close, isRepeat: true))
            #expect(QuickLookSource.shouldHandle(.up, isRepeat: true))
            #expect(QuickLookSource.shouldHandle(.down, isRepeat: true))
        }

        /// Outside the inert host, Settings is opened by performing the app menu's ⌘, item.
        @Test func settingsOpensThroughTheMenuOutsideTheInertHost() {
            let target = SettingsTarget()
            let menu = NSMenu()
            let item = NSMenuItem(title: "Settings…", action: #selector(SettingsTarget.settings), keyEquivalent: ",")
            item.target = target
            menu.addItem(item)
            var activations = 0
            let saved = AppActivation.activate
            AppActivation.activate = { activations += 1 }
            defer { AppActivation.activate = saved }

            #expect(PanelController.openSettingsWindow(inert: false, menu: menu))
            #expect(target.hits == 1)
            #expect(activations == 1, "brought forward first, or Settings opens behind the front app")
            // No ⌘, item: reported, nothing performed.
            #expect(!PanelController.openSettingsWindow(inert: false, menu: NSMenu()))
            #expect(target.hits == 1)
        }

        /// Installing connects the panel to the app; in test mode it neither registers
        /// the hotkey nor shows the panel.
        @Test func installConnectsTheAppWithoutShowing() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            let items: [ResultItem] = [.file(Wire.hit("/p/a b.txt"))]
            pc.perform(.copyPath(0), items)
            #expect(env.pasteboard.string(forType: .string) == nil, "not connected yet")
            pc.install(app: env.app)
            #expect(!pc.isVisible)
            pc.perform(.copyPath(0), items)
            #expect(env.pasteboard.string(forType: .string) == "/p/a b.txt")
        }

        /// Focus is requested only after activation and presentation, on both first open and reused-view reopens.
        @Test func focusIsRequestedAfterActivationAndOnReopen() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            var triggerDuringActivate: [Int] = []
            let saved = AppActivation.activate
            AppActivation.activate = { triggerDuringActivate.append(pc.viewState.focusTrigger) }
            defer { AppActivation.activate = saved }

            pc.show(app: env.app)
            #expect(triggerDuringActivate == [0], "focusTrigger must not bump before activation")
            #expect(pc.viewState.focusTrigger == 1)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }

            pc.hide(returnFocus: false)
            pc.show(app: env.app)
            #expect(triggerDuringActivate == [0, 1], "reopen must also wait until after activation")
            #expect(pc.viewState.focusTrigger == 2)
            // Hiding before the deferred focus turn runs must not crash or disturb state.
            pc.hide(returnFocus: false)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            #expect(!pc.isVisible)
        }

        /// Reusing the hosting view keeps cached row frames so ⌘K still anchors to unchanged rows; rebuilding clears them.
        @Test func reopeningWithSameAppPreservesRowGeometryAndSwitchingAppClearsIt() {
            let env1 = TestEnv()
            defer { env1.tearDown() }
            let env2 = TestEnv()
            defer { env2.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }

            let rowRect = CGRect(x: 0, y: 100, width: 680, height: 40)
            pc.show(app: env1.app)
            pc.geometry.rows["file:/p/a.txt"] = rowRect
            pc.hide(returnFocus: false)

            pc.show(app: env1.app)
            #expect(pc.geometry.rows["file:/p/a.txt"] == rowRect, "reused hosting view must keep row frames for ⌘K")

            pc.hide(returnFocus: false)
            pc.show(app: env2.app)
            #expect(pc.geometry.rows["file:/p/a.txt"] == nil, "rebuilding contentView clears stale row frames")
        }
    }
}

private final class SettingsTarget: NSObject {
    var hits = 0
    @objc func settings() { hits += 1 }
}
