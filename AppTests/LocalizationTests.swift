import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Verifies the English String Catalog is configured and compiled into the app bundle.
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
                    "Welcome to FSearch",
                    "Move to Trash",
                    "Move FSearch to Applications",
                    "Search Files",
                    "“%@” is gone: moved or deleted",
                ] {
                    #expect(table[key] == key, "missing compiled catalog entry for \(key)")
                }
            }
        }

        @Test func appKitAndSwiftUIStringsResolveInEnglish() {
            #expect(String(localized: "Search files", bundle: .main) == "Search files")
            #expect(String(localized: "Welcome to FSearch", bundle: .main) == "Welcome to FSearch")
            #expect(String(localized: "Move to Trash", bundle: .main) == "Move to Trash")
            #expect(String(localized: "Move FSearch to Applications", bundle: .main) == "Move FSearch to Applications")
            #expect(FileActions.missingMessage("/p/report.pdf") == "“report.pdf” is gone: moved or deleted")
        }
    }
}
