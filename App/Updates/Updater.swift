import SwiftUI
import Sparkle

/// Sparkle updater. Not started while Info.plist still carries the placeholder
/// public key (see docs/release-checklist.md), so dev builds never prompt.
@MainActor
enum Updater {
    static let isConfigured: Bool = {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != "REPLACE_WITH_SPARKLE_PUBLIC_KEY"
    }()

    static let controller = SPUStandardUpdaterController(
        startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
}

/// Menu item: hidden while the Sparkle key is the placeholder.
struct CheckForUpdatesItem: View {
    var body: some View {
        if Updater.isConfigured {
            Button("Check for Updates…") { Updater.controller.checkForUpdates(nil) }
        }
    }
}
