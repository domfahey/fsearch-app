import Foundation
import Testing

@testable import FSearchKit

@Suite
struct LocalizationTests {
    private static let supportedLocales = ["en", "de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans"]

    private static let requiredKeys = [
        "The background helper isn't answering",
        "FSearch Settings",
        "Send Feedback",
        "Can't reach the search daemon",
        "files with these extensions",
        "Turn On Full Disk Access…",
        "New Search Window",
        "Search Window…",
    ]

    @Test func fsearchKitModuleBundleCarriesAllSupportedLocalizations() throws {
        let bundle = Bundle.module
        if let stringsURL = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en") {
            let table = try #require(NSDictionary(contentsOf: stringsURL) as? [String: String])
            for key in Self.requiredKeys {
                #expect(table[key] == key, "missing compiled FSearchKit entry for \(key)")
            }
            for locale in Self.supportedLocales where locale != "en" {
                let locURL = try #require(
                    bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: locale),
                    "missing compiled FSearchKit localization for \(locale)")
                let locTable = try #require(NSDictionary(contentsOf: locURL) as? [String: String])
                for key in Self.requiredKeys {
                    #expect(!(locTable[key] ?? "").isEmpty, "missing \(locale) FSearchKit entry for \(key)")
                }
            }
            return
        }

        // SwiftPM CLI (`swift test`) copies `.xcstrings` verbatim into Bundle.module; Xcode compiles it into `.strings`.
        let catalogURL = try #require(bundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["sourceLanguage"] as? String) == "en")
        let strings = try #require(json["strings"] as? [String: [String: Any]])
        for (key, entry) in strings {
            if (entry["shouldTranslate"] as? Bool) == false { continue }
            let locs = try #require(entry["localizations"] as? [String: [String: Any]], "missing localizations for \(key)")
            for locale in Self.supportedLocales {
                let unit = try #require(locs[locale]?["stringUnit"] as? [String: String], "missing \(locale) for \(key)")
                #expect(unit["state"] == "translated", "\(locale) not translated for \(key)")
                #expect(!(unit["value"] ?? "").isEmpty, "empty \(locale) value for \(key)")
            }
        }
        for key in Self.requiredKeys {
            let entry = try #require(strings[key], "missing FSearchKit catalog entry for \(key)")
            let locs = try #require(entry["localizations"] as? [String: [String: Any]])
            let unit = try #require(locs["en"]?["stringUnit"] as? [String: String])
            #expect(unit["value"] == key)
        }
    }

    @Test func panelMenuItemIDsAreStableEnglishIdentifiers() {
        let items = PanelMenuModel.sections.flatMap(\.items)
        #expect(
            items.map(\.id) == [
                "Send Feedback", "Manual", "Keyboard Shortcuts", "Changelog", "About FSearch", "Search Window", "Settings",
                "GitHub", "Discussions", "Quit FSearch",
            ])
    }
}
