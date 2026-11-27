import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Verifies both the app and FSearchKit String Catalogs compile all 8 supported localizations into the app bundle.
    @Suite @MainActor
    struct LocalizationTests {
        private static let supportedLocales = ["en", "de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans"]

        @Test func bundleDeclaresEnglishDevelopmentRegionAndCompiledStringCatalog() throws {
            #expect(Bundle.main.developmentLocalization == "en")
            for locale in Self.supportedLocales {
                #expect(Bundle.main.localizations.contains(locale), "missing \(locale) in Bundle.main.localizations")
            }

            let stringsURL = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
            let loctableURL = Bundle.main.url(forResource: "Localizable", withExtension: "loctable")
            #expect(stringsURL != nil || loctableURL != nil, "Localizable.xcstrings must compile into the app bundle")

            if let loctableURL {
                let loctable = try #require(NSDictionary(contentsOf: loctableURL) as? [String: [String: Any]])
                for locale in Self.supportedLocales {
                    let table = try #require(loctable[locale], "missing \(locale) table in Localizable.loctable")
                    #expect((table["Search files"] as? String)?.isEmpty == false, "missing \(locale) 'Search files'")
                    #expect((table["New Search Window…"] as? String)?.isEmpty == false, "missing \(locale) 'New Search Window…'")
                }
            }

            if let stringsURL {
                let table = try #require(NSDictionary(contentsOf: stringsURL) as? [String: String])
                for key in [
                    "Search files",
                    "Recent",
                    "Inside files",
                    "Search inside files",
                    "Find definitions",
                    "Use “%@” with…",
                    "Open at line",
                    "Actions",
                    "Entries",
                    "Default app",
                    "FSearch Help",
                    "Turn on FSearch",
                    "FSearch won't open when you log in.",
                    "The background helper stopped answering.",
                    "Welcome to FSearch",
                    "Move to Trash",
                    "Move FSearch to Applications",
                    "Search Files",
                    "“%@” is gone: moved or deleted",
                    "New Search Window…",
                ] {
                    #expect(table[key] == key, "missing compiled catalog entry for \(key)")
                }
                for technical in ["", "searching", "done", "selected", "%lld", "%@, %@"] {
                    #expect(table[technical] == nil, "technical key \(technical) should not be in compiled Localizable.strings")
                }
            }
        }

        @Test func embeddedFSearchKitResourceBundleHasAllCompiledLocalizations() throws {
            let kitBundleURL = try #require(Bundle.main.url(forResource: "FSearchKit_FSearchKit", withExtension: "bundle"))
            let kitBundle = try #require(Bundle(url: kitBundleURL))
            let stringsURL = kitBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
            let loctableURL = kitBundle.url(forResource: "Localizable", withExtension: "loctable")
            #expect(stringsURL != nil || loctableURL != nil)
            if let loctableURL {
                let loctable = try #require(NSDictionary(contentsOf: loctableURL) as? [String: [String: Any]])
                for locale in Self.supportedLocales {
                    let table = try #require(loctable[locale], "missing \(locale) in FSearchKit Localizable.loctable")
                    #expect((table["FSearch Settings"] as? String)?.isEmpty == false, "missing \(locale) 'FSearch Settings'")
                }
            }
        }

        @Test func appKitAndSwiftUIStringsResolveInEnglish() {
            #expect(String(localized: "Search files", bundle: .main) == "Search files")
            #expect(String(localized: "Welcome to FSearch", bundle: .main) == "Welcome to FSearch")
            #expect(String(localized: "Move to Trash", bundle: .main) == "Move to Trash")
            #expect(String(localized: "Move FSearch to Applications", bundle: .main) == "Move FSearch to Applications")
            #expect(FileActions.missingMessage("/p/report.pdf") == "“report.pdf” is gone: moved or deleted")
            #expect(UserMessage.forPhase(.failed(.disconnected), helperGaveUp: true) == "The background helper isn't answering")
        }
    }
}
