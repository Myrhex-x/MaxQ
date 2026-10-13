//
//  AddressAndSearchTests.swift
//  Max Q
//

import Foundation
import Testing
@testable import MaxQ

struct AddressInputTests {
    private func url(_ input: String) -> String? {
        if case .url(let url) = AddressInput.classify(input) { return url.absoluteString }
        return nil
    }

    private func isSearch(_ input: String) -> Bool {
        if case .search = AddressInput.classify(input) { return true }
        return false
    }

    @Test func bareDomainsBecomeHTTPS() {
        #expect(url("grok.com") == "https://grok.com")
        #expect(url("x.com/home") == "https://x.com/home")
        #expect(url("news.bbc.co.uk") == "https://news.bbc.co.uk")
        #expect(url("example.io?x=1") == "https://example.io?x=1")
    }

    @Test func explicitSchemesAreKept() {
        #expect(url("http://example.com") == "http://example.com")
        #expect(url("https://grokipedia.com/page/Mars") == "https://grokipedia.com/page/Mars")
        #expect(url("about:blank") == "about:blank")
        #expect(url("mailto:someone@example.com") == "mailto:someone@example.com")
    }

    @Test func localAndIPAddressesUseHTTP() {
        #expect(url("localhost:3000") == "http://localhost:3000")
        #expect(url("localhost") == "http://localhost")
        #expect(url("192.168.1.10:8080/admin") == "http://192.168.1.10:8080/admin")
        #expect(url("example.com:8443/path") == "https://example.com:8443/path")
    }

    @Test func questionsAndWordsAreSearches() {
        #expect(isSearch("what is max q"))
        #expect(isSearch("grok"))
        #expect(isSearch("node.js"))          // not a real TLD
        #expect(isSearch("1.5"))
        #expect(isSearch("define:grok"))
        #expect(isSearch("user@example.com"))
        #expect(isSearch("https:/broken.com"))
    }

    @Test func dangerousSchemesNeverNavigate() {
        #expect(isSearch("javascript:alert(1)"))
        #expect(isSearch("JavaScript:alert(1)"))
        #expect(isSearch("data:text/html,<b>hi</b>"))
        #expect(isSearch("vbscript:msgbox"))
    }

    @Test func emptyInputIsNothing() {
        #expect(AddressInput.classify("   ") == nil)
    }

    @Test func ipv4Validation() {
        #expect(AddressInput.isIPv4("10.0.0.1"))
        #expect(!AddressInput.isIPv4("256.1.1.1"))
        #expect(!AddressInput.isIPv4("1.2.3"))
    }
}

struct SearchEngineTests {
    @Test func searchURLEncodesTheQuery() throws {
        let ddg = try #require(SearchEngine.builtIn(.duckduckgo))
        #expect(ddg.searchURL(for: "max q & grok")?.absoluteString == "https://duckduckgo.com/?q=max%20q%20%26%20grok")
        let google = try #require(SearchEngine.builtIn(.google))
        #expect(google.searchURL(for: "a+b=c")?.absoluteString == "https://www.google.com/search?q=a%2Bb%3Dc")
    }

    @Test func readsTheQueryBackFromResultsPages() throws {
        let ddg = try #require(SearchEngine.builtIn(.duckduckgo))
        #expect(ddg.query(fromResultsURL: URL(string: "https://duckduckgo.com/?q=grok+4.7&t=h_&ia=web")!) == "grok 4.7")
        #expect(ddg.query(fromResultsURL: URL(string: "https://duckduckgo.com/?q=elon+musk")!) == "elon musk")
        #expect(ddg.query(fromResultsURL: URL(string: "https://duckduckgo.com/?q=c%2B%2B+tutorial")!) == "c++ tutorial")
        #expect(ddg.query(fromResultsURL: URL(string: "https://duckduckgo.com/?q=grok%204.7")!) == "grok 4.7")
        #expect(ddg.query(fromResultsURL: URL(string: "https://example.com/?q=grok")!) == nil)

        let google = try #require(SearchEngine.builtIn(.google))
        #expect(google.query(fromResultsURL: URL(string: "https://www.google.com/search?q=spacex&hl=en")!) == "spacex")
        #expect(google.query(fromResultsURL: URL(string: "https://google.com/search?q=spacex")!) == "spacex")
        #expect(google.query(fromResultsURL: URL(string: "https://www.google.com/maps?q=spacex")!) == nil)

        let brave = try #require(SearchEngine.builtIn(.brave))
        #expect(brave.query(fromResultsURL: URL(string: "https://search.brave.com/search?q=mars&source=web")!) == "mars")
    }

    @Test func customTemplatesMustBeHTTPSWithOnePlaceholder() {
        #expect(SearchEngine.isValidTemplate("https://search.example.org/search?q=%s"))
        #expect(!SearchEngine.isValidTemplate("http://search.example.org/search?q=%s"))
        #expect(!SearchEngine.isValidTemplate("https://search.example.org/search?q=%s&r=%s"))
        #expect(!SearchEngine.isValidTemplate("https://search.example.org/search"))
        let custom = SearchEngine.custom(template: "https://searx.example.net/search?q=%s")
        #expect(custom?.name == "searx.example.net")
        #expect(custom?.query(fromResultsURL: URL(string: "https://searx.example.net/search?q=hello")!) == "hello")
    }

    @Test func parsesOpenSearchSuggestions() {
        let payload = Data(#"["grok", ["grok 4.7", "grok imagine", "grokipedia"], [], []]"#.utf8)
        #expect(SearchEngine.parseSuggestions(payload) == ["grok 4.7", "grok imagine", "grokipedia"])
        #expect(SearchEngine.parseSuggestions(Data("not json".utf8)).isEmpty)
        #expect(SearchEngine.parseSuggestions(Data(#"{"q": 1}"#.utf8)).isEmpty)
    }
}

struct LinkTests {
    @Test func xIntentCarriesTitleAndURL() throws {
        let intent = try #require(XLinks.intent(text: "Starship flight 12", url: URL(string: "https://example.com/a?b=c")!))
        let items = URLComponents(url: intent, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(intent.host == "x.com")
        #expect(intent.path == "/intent/post")
        #expect(items.first { $0.name == "text" }?.value == "Starship flight 12")
        #expect(items.first { $0.name == "url" }?.value == "https://example.com/a?b=c")
    }

    @Test func xSearchURL() {
        let url = XLinks.search(for: "max q browser")
        #expect(url?.absoluteString == "https://x.com/search?q=max%20q%20browser&src=typed_query")
        #expect(XLinks.search(for: "   ") == nil)
    }

    @Test func grokipediaSearchURL() {
        #expect(GrokipediaLinks.search("Elon Musk")?.absoluteString == "https://grokipedia.com/search?q=Elon%20Musk")
    }

    @Test func topicDetection() {
        #expect(GrokipediaLinks.looksLikeTopic("Mars"))
        #expect(GrokipediaLinks.looksLikeTopic("Kármán line"))
        #expect(GrokipediaLinks.looksLikeTopic("SpaceX Starship"))
        #expect(!GrokipediaLinks.looksLikeTopic("how to change a tire"))
        #expect(!GrokipediaLinks.looksLikeTopic("is it raining?"))
        #expect(!GrokipediaLinks.looksLikeTopic("iphone vs pixel"))
        #expect(!GrokipediaLinks.looksLikeTopic("weather paris"))
        #expect(!GrokipediaLinks.looksLikeTopic("order 123456789"))
        #expect(!GrokipediaLinks.looksLikeTopic("one two three four five six"))
    }

    @Test func botMailtoKeepsInstructionAndLink() throws {
        let url = try #require(GrokBot.mailto(address: "mybot@mail.grokbot.com", pageTitle: "Launch schedule",
                                              pageURL: URL(string: "https://example.com/launches")!,
                                              instruction: "Add these to my calendar"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "mybot@mail.grokbot.com")
        #expect(components.queryItems?.first { $0.name == "subject" }?.value == "Launch schedule")
        #expect(components.queryItems?.first { $0.name == "body" }?.value == "Add these to my calendar\n\nhttps://example.com/launches")
    }

    @Test func emailPlausibility() {
        #expect(AppSettings.isPlausibleEmail("bot@mail.grokbot.com"))
        #expect(!AppSettings.isPlausibleEmail("bot@localhost"))
        #expect(!AppSettings.isPlausibleEmail("bot mail@x.com"))
        #expect(!AppSettings.isPlausibleEmail("@x.com"))
        #expect(!AppSettings.isPlausibleEmail("a@b@c.com"))
    }

    @Test func domainEmphasis() {
        #expect(DomainDisplay.split(host: "news.example.com") == ("news.", "example.com"))
        #expect(DomainDisplay.split(host: "www.bbc.co.uk") == ("www.", "bbc.co.uk"))
        #expect(DomainDisplay.split(host: "apple.com.evil.example") == ("apple.com.", "evil.example"))
        #expect(DomainDisplay.split(host: "x.com") == ("", "x.com"))
    }

    @Test func faviconLinksPreferLargeAppleTouchIcons() {
        let html = """
        <html><head>
        <link rel="icon" href="/favicon-32.png" sizes="32x32">
        <link rel='apple-touch-icon' href='https://cdn.example.com/touch.png'>
        <link rel="mask-icon" href="/mask.svg">
        <link rel="icon" type="image/svg+xml" href="/icon.svg">
        <link rel="stylesheet" href="/style.css">
        </head></html>
        """
        let links = FaviconStore.iconLinks(inHTML: html, baseURL: URL(string: "https://example.com/page")!)
        #expect(links.first?.absoluteString == "https://cdn.example.com/touch.png")
        #expect(links.contains(URL(string: "https://example.com/favicon-32.png")!))
        #expect(!links.contains { $0.path.hasSuffix(".css") })
        #expect(links.last?.lastPathComponent == "mask.svg")
    }
}

struct BangTests {
    @Test func readsTheShortcutFirstOrLast() {
        #expect(Bangs.parse("!yt lofi beats")?.bang.trigger == "yt")
        #expect(Bangs.parse("!yt lofi beats")?.words == "lofi beats")
        #expect(Bangs.parse("lofi beats !yt")?.words == "lofi beats")
        #expect(Bangs.parse("!YOUTUBE lofi")?.bang.name == "YouTube")
        #expect(Bangs.parse("!x")?.words == "")
    }

    @Test func leavesOtherTextAlone() {
        #expect(Bangs.parse("lofi beats") == nil)
        #expect(Bangs.parse("!nosuchbang lofi") == nil)
        #expect(Bangs.parse("!") == nil)
        // Only the first or last word counts.
        #expect(Bangs.parse("lofi !yt beats") == nil)
        #expect(Bangs.parse("!yt") != nil)
    }

    @Test func buildsTheSitesSearch() {
        let youtube = Bangs.find("yt")!
        #expect(youtube.url(for: "c++ & go")?.absoluteString == "https://www.youtube.com/results?search_query=c%2B%2B%20%26%20go")
        #expect(youtube.url(for: "")?.absoluteString == "https://www.youtube.com")
        // Max Q's own tabs fall back to the sites' own search pages.
        #expect(Bangs.find("x")?.url(for: "starship")?.host == "x.com")
        #expect(Bangs.find("gp")?.url(for: "mars")?.host == "grokipedia.com")
        #expect(Bangs.find("grok")?.url(for: "hi") == nil)
    }

    @Test func completesWhileTyping() {
        #expect(Bangs.completions(for: "!").count == 7)
        #expect(Bangs.completions(for: "!y").first?.trigger == "yt")
        #expect(Bangs.completions(for: "!wiki").first?.trigger == "w")
        #expect(Bangs.completions(for: "!yt lofi").isEmpty)
        #expect(Bangs.completions(for: "yt").isEmpty)
        // Names count too: "!hack" finds Hacker News.
        #expect(Bangs.completions(for: "!hack").first?.trigger == "hn")
    }

    @Test func opensResultsPagesOnATab() {
        let url = MaxQScheme.searchURL(for: "starship", tab: .x)
        #expect(url?.absoluteString == "maxq://search?q=starship&tab=x")
        #expect(MaxQScheme.tab(from: url) == .x)
        #expect(MaxQScheme.query(from: url) == "starship")
        #expect(MaxQScheme.searchURL(for: "starship")?.absoluteString == "maxq://search?q=starship")
        #expect(MaxQScheme.tab(from: MaxQScheme.searchURL(for: "starship")) == nil)
    }
}

struct QuickAnswerTests {
    @Test func works_out_sums() {
        #expect(Calculator.evaluate("12*7+3", decimalSeparator: ".") == 87)
        #expect(Calculator.evaluate("2^10", decimalSeparator: ".") == 1024)
        #expect(Calculator.evaluate("15% of 240", decimalSeparator: ".") == 36)
        #expect(Calculator.evaluate("20% off 80", decimalSeparator: ".") == 64)
        #expect(Calculator.evaluate("(3+4)*5", decimalSeparator: ".") == 35)
        #expect(Calculator.evaluate("2(3+4)", decimalSeparator: ".") == 14)
        #expect(Calculator.evaluate("sqrt(16) + 1", decimalSeparator: ".") == 5)
        #expect(Calculator.evaluate("3x4", decimalSeparator: ".") == 12)
        #expect(Calculator.evaluate("1,000 + 1", decimalSeparator: ".") == 1001)
        #expect(Calculator.evaluate("3,5 + 1", decimalSeparator: ",") == 4.5)
        #expect(Calculator.evaluate("5!", decimalSeparator: ".") == 120)
        #expect(Calculator.evaluate("10 mod 3", decimalSeparator: ".") == 1)
        #expect(Calculator.evaluate("-2 + 5", decimalSeparator: ".") == 3)
    }

    @Test func leaves_other_searches_alone() {
        for text in ["42", "pi", "2026-10-10", "10/10/2026", "555-1234", "iphone 16", "covid 19", "1/2 cup", "7-11", "1/0"] {
            #expect(Calculator.evaluate(text, decimalSeparator: ".") == nil, "\(text)")
        }
    }

    @Test func converts_units() {
        let km = UnitConversion.parse("10 km in miles", decimalSeparator: ".")
        #expect(km != nil)
        #expect(abs((km?.result ?? 0) - 6.21371) < 0.0001)
        #expect(abs((UnitConversion.parse("212 f to c", decimalSeparator: ".")?.result ?? 0) - 100) < 0.001)
        #expect(UnitConversion.parse("70 kg to lbs", decimalSeparator: ".") != nil)
        #expect(UnitConversion.parse("1 tb in gb", decimalSeparator: ".")?.result == 1000)
        #expect(UnitConversion.parse("10 km in kg", decimalSeparator: ".") == nil)
        #expect(UnitConversion.parse("1 direction in london", decimalSeparator: ".") == nil)
    }

    @Test func reads_currency_searches() {
        let dollars = CurrencyQuery.parse("100 usd to eur", decimalSeparator: ".")
        #expect(dollars?.amount == 100 && dollars?.from == "USD" && dollars?.to == "EUR")
        #expect(CurrencyQuery.parse("€50 in dollars", decimalSeparator: ".")?.from == "EUR")
        #expect(CurrencyQuery.parse("20 pounds in euros", decimalSeparator: ".")?.from == "GBP")
        // Pounds to kilograms is a weight, not money.
        #expect(CurrencyQuery.parse("20 pounds in kg", decimalSeparator: ".") == nil)
        if case .conversion = QuickAnswerRequest.detect("20 pounds in kg") {} else { Issue.record("pounds to kg") }
    }

    @Test func finds_times_and_weather() {
        #expect(TimeQuery.parse("time in tokyo")?.zone.identifier == "Asia/Tokyo")
        #expect(TimeQuery.parse("new york time")?.zone.identifier == "America/New_York")
        #expect(TimeQuery.parse("what time is it in paris")?.city == "Paris")
        #expect(TimeQuery.parse("time pst") != nil)
        #expect(TimeQuery.parse("screen time") == nil)
        #expect(TimeQuery.parse("time cat") == nil)
        #expect(WeatherQuery.parse("weather in paris") == "paris")
        #expect(WeatherQuery.parse("tokyo weather") == "tokyo")
        #expect(WeatherQuery.parse("weather") == "")
        #expect(WeatherQuery.parse("forecast for tomorrow") == "")
        #expect(WeatherQuery.parse("weather app") == nil)
        #expect(WeatherQuery.parse("body temperature") == nil)
        // Answered here, so Grok isn't asked (or paid).
        #expect(!GrokSearch.wantsAnswer("weather in paris"))
        #expect(!GrokSearch.wantsAnswer("12*7"))
        #expect(GrokSearch.wantsAnswer("spacex starship"))
    }

    @Test func reads_open_meteo() throws {
        let json = """
        {"current":{"temperature_2m":18.4,"apparent_temperature":17.1,"relative_humidity_2m":62,"weather_code":2,"wind_speed_10m":12.3,"is_day":1},
         "daily":{"time":["2026-10-10","2026-10-11"],"weather_code":[2,61],"temperature_2m_max":[19.5,16],"temperature_2m_min":[11.2,9],"precipitation_probability_max":[10,80]}}
        """
        let report = try WeatherClient.parse(Data(json.utf8), place: "Paris", region: "France", fahrenheit: false)
        #expect(report.temperature == 18.4)
        #expect(report.days.count == 2)
        #expect(report.days[1].precipitation == 80)
        #expect(WeatherCondition.label(report.code) == "Partly cloudy")
    }
}

struct UnreadCountTests {
    @Test func readsTheCountInATitle() {
        #expect(BrowserTab.unreadCount(in: "(3) Home / X") == "3")
        #expect(BrowserTab.unreadCount(in: "(20+) Notifications / X") == "20+")
        #expect(BrowserTab.unreadCount(in: "Home / X") == nil)
        #expect(BrowserTab.unreadCount(in: "(0) Home / X") == nil)
        #expect(BrowserTab.unreadCount(in: "(Draft) Post") == nil)
    }
}

struct XPageQueryTests {
    @Test func searchesThePagesLink() {
        #expect(XLinks.linkQuery(for: URL(string: "https://www.theverge.com/2026/10/9/starship/?utm_source=x#top")!) == "theverge.com/2026/10/9/starship")
        #expect(XLinks.linkQuery(for: URL(string: "https://spacex.com/")!) == "spacex.com")
        #expect(XLinks.linkQuery(for: URL(string: "maxq://search?q=x")!) == nil)
        #expect(XLinks.search(for: "a", latest: true)?.absoluteString.hasSuffix("f=live") == true)
    }

    @Test func searchesTheTitleWithoutTheSite() {
        #expect(XLinks.titleQuery(for: "Starship flies again - The Verge") == "\"Starship flies again\"")
        #expect(XLinks.titleQuery(for: "SpaceX | Starship flight 14 recap") == "\"SpaceX | Starship flight 14 recap\"")
        #expect(XLinks.titleQuery(for: "X") == nil)
    }
}

struct CommandBarTests {
    @Test func matchesWordsInAnyOrder() {
        #expect(CommandBar.matches("The Verge: Starship flies again", "starship verge"))
        #expect(CommandBar.matches("Café menu", "cafe"))
        #expect(!CommandBar.matches("The Verge", "starship"))
    }

    @Test func quotesThePageAroundTheMatch() {
        let text = "Plans and pricing. The Pro plan costs 20 dollars a month and includes everything in the basic plan."
        let snippet = CommandBar.snippet(in: text, matching: "costs 20", radius: 20)
        let plain = snippet.map { String($0.characters) } ?? ""
        #expect(plain.contains("costs 20"))
        #expect(plain.hasPrefix("…"))
        #expect(CommandBar.snippet(in: text, matching: "zz") == nil)
    }
}
