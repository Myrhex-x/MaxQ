//
//  FrenchTests.swift
//  Max Q
//
//  Max Q in French: the compiled table, read the way the app reads it.
//

import Foundation
import Testing
@testable import MaxQ

struct FrenchTests {
    private func french() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "fr", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func table() throws -> [String: String] {
        let url = try #require(try french().url(forResource: "Localizable", withExtension: "strings"))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test func translatesTheInterface() throws {
        let fr = try french()
        func t(_ key: String) -> String { fr.localizedString(forKey: key, value: nil, table: nil) }
        #expect(t("New Tab") == "Nouvel onglet")
        #expect(t("Settings") == "Réglages")
        #expect(t("Ask Grok") == "Demander à Grok")
        #expect(t("Posts on X") == "Posts sur X")
        // Words that mean something else elsewhere get their own key.
        #expect(t("Clear") == "Effacer")
        #expect(t("weather.clear") == "Dégagé")
    }

    /// French typography: a narrow no-break space before ? ! and ;, a no-break space before : and
    /// inside « », so a line never starts with the mark.
    @Test func setsFrenchPunctuation() throws {
        let fr = try french()
        #expect(fr.localizedString(forKey: "What do you want to know?", value: nil, table: nil) == "Que voulez-vous savoir\u{202F}?")
        for (key, value) in try table() {
            #expect(![" ?", " !", " :", " ;", "« ", " »"].contains { value.contains($0) }, "\(key) → \(value)")
        }
    }

    /// SpaceXAI bills in dollars, and each language writes them its own way.
    @Test func writesDollarsTheLocalWay() {
        #expect(Money.usd(1.2, locale: Locale(identifier: "en_US")) == "$1.20")
        #expect(Money.usd(1.2, locale: Locale(identifier: "fr_FR")) == "1,20\u{A0}$US")
        #expect(Money.usd(1234.5, locale: Locale(identifier: "fr_FR")) == "1\u{202F}234,50\u{A0}$US")
        #expect(Money.usd(0.0012, digits: 4, locale: Locale(identifier: "fr_FR")) == "0,0012\u{A0}$US")
    }

    /// Max Q's copy never uses em or en dashes, in any language.
    @Test func hasNoDashes() throws {
        let table = try table()
        #expect(table.count > 700)
        for (key, value) in table {
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) → \(value)")
        }
    }

    /// Every argument of the English string is still there in French, and of the same kind.
    @Test func keepsEveryArgument() throws {
        let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?(lld|ld|d|@|s|f)"#)
        func kinds(_ text: String) -> [String] {
            let text = text.replacingOccurrences(of: "%%", with: "") as NSString
            return pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length))
                .map { text.substring(with: $0.range(at: 1)) }
                .sorted()
        }
        for (key, value) in try table() {
            #expect(kinds(key) == kinds(value), "\(key) → \(value)")
        }
    }
}
