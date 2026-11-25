import Foundation
import Testing

@testable import FSearchKit

@Suite
struct LocalizationTests {
    private static let requiredKeys = [
        "The search helper isn't answering",
        "FSearch Settings",
        "Send Feedback",
        "Can't reach the search daemon",
        "files with these extensions",
        "Turn On Full Disk Access…",
    ]

    @Test func fsearchKitModuleBundleCarriesEnglishStringCatalog() throws {
        let bundle = Bundle.module
        if let stringsURL = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en") {
            let table = try #require(NSDictionary(contentsOf: stringsURL) as? [String: String])
            for key in Self.requiredKeys {
                #expect(table[key] == key, "missing compiled FSearchKit entry for \(key)")
            }
            return
        }

        // SwiftPM CLI (`swift test`) copies `.xcstrings` verbatim into Bundle.module; Xcode compiles it into `.strings`.
        let catalogURL = try #require(bundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["sourceLanguage"] as? String) == "en")
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for key in Self.requiredKeys {
            let entry = try #require(strings[key], "missing FSearchKit catalog entry for \(key)")
            let locs = try #require(entry["localizations"] as? [String: [String: Any]])
            let unit = try #require(locs["en"]?["stringUnit"] as? [String: String])
            #expect(unit["state"] == "translated")
            #expect(unit["value"] == key)
        }
    }

    @Test func panelMenuItemIDsAreStableEnglishIdentifiers() {
        let items = PanelMenuModel.sections.flatMap(\.items)
        #expect(
            items.map(\.id) == [
                "Send Feedback", "Manual", "Keyboard Shortcuts", "Changelog", "About FSearch", "Settings",
                "GitHub", "Discussions", "Quit FSearch",
            ])
    }
}
