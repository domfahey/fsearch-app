import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Verifies both the app and FSearchKit English String Catalogs are configured and compiled into the app bundle.
    @Suite @MainActor
    struct LocalizationTests {
        @Test func bundleDeclaresEnglishDevelopmentRegionAndCompiledStringCatalog() throws {
            #expect(Bundle.main.developmentLocalization == "en")
            #expect(Bundle.main.localizations.contains("en"))

            let stringsURL = Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
            let loctableURL = Bundle.main.url(forResource: "Localizable", withExtension: "loctable")
            #expect(stringsURL != nil || loctableURL != nil, "Localizable.xcstrings must compile into the app bundle")

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
                ] {
                    #expect(table[key] == key, "missing compiled catalog entry for \(key)")
                }
                for technical in ["", "searching", "done", "selected", "%lld", "%@, %@"] {
                    #expect(table[technical] == nil, "technical key \(technical) should not be in compiled Localizable.strings")
                }
            }
        }

        @Test func embeddedFSearchKitResourceBundleHasCompiledEnglishCatalog() throws {
            let kitBundleURL = try #require(Bundle.main.url(forResource: "FSearchKit_FSearchKit", withExtension: "bundle"))
            let kitBundle = try #require(Bundle(url: kitBundleURL))
            let stringsURL = kitBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en")
            let loctableURL = kitBundle.url(forResource: "Localizable", withExtension: "loctable")
            #expect(stringsURL != nil || loctableURL != nil)
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
