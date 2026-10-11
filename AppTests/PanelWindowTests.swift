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

        /// The launcher hands the preview its data source and takes it back when the preview closes.
        @Test func quickLookControlIsHandedOverAndBack() throws {
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
    }
}

private final class SettingsTarget: NSObject {
    var hits = 0
    @objc func settings() { hits += 1 }
}
