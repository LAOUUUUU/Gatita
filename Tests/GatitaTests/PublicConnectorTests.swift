//
//  PublicConnectorTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The connectors that read free public services: weather, Wikipedia, a dictionary, exchange rates, package
/// registries, Stack Overflow, and public GitHub repos. Each one's address and text are tested with fixtures
/// shaped like the real answers, so the tests never touch the network.
final class PublicConnectorTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Catalog

    func testEveryConnectorToolHasHelpAndRunsEverywhere() {
        for id in ["weather", "wikipedia", "dictionary", "currency", "packages", "stackoverflow", "repos"] {
            guard let connector = Connectors.connector(named: id) else { return XCTFail("missing connector \(id)") }
            XCTAssertFalse(connector.macOnly, id)
            XCTAssertEqual(Connectors.toolHelp(for: connector).count, connector.tools.count, id)
            XCTAssertTrue(GatitaMode.chat.allows(connector: id, hasProject: false), "\(id) works in Chat")
        }
    }

    func testToolNamesBelongToOneConnectorEach() {
        let names = Connectors.catalog.flatMap(\.tools)
        XCTAssertEqual(names.count, Set(names).count)
    }

    // MARK: - Weather

    func testWeatherLooksUpThePlaceByNameOnly() throws {
        let url = try Weather.geocodeURL(place: "Toronto, Canada")
        XCTAssertEqual(url.host, "geocoding-api.open-meteo.com")
        XCTAssertTrue(url.absoluteString.contains("name=Toronto"), url.absoluteString)
        XCTAssertThrowsError(try Weather.geocodeURL(place: "  "))
    }

    func testWeatherPicksThePlaceThatMatchesTheRegion() throws {
        let results = data(#"{"results":[{"name":"Toronto","latitude":43.70643,"longitude":-79.39864,"country":"Canada","admin1":"Ontario","country_code":"CA"},{"name":"Toronto","latitude":40.46423,"longitude":-80.60091,"country":"United States","admin1":"Ohio","country_code":"US"}]}"#)
        XCTAssertEqual(try Weather.pickPlace(results, query: "Toronto, Ohio").admin1, "Ohio")
        XCTAssertEqual(try Weather.pickPlace(results, query: "Toronto").country, "Canada")
        XCTAssertThrowsError(try Weather.pickPlace(data(#"{"generationtime_ms":0.5}"#), query: "Nowhere"))
    }

    func testTheForecastAddressAsksForTheDaysAndUnits() {
        let place = Weather.Place(name: "Toronto", admin1: "Ontario", country: "Canada", latitude: 43.7, longitude: -79.4)
        let url = Weather.forecastURL(place, days: 3, imperial: true).absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/v1/forecast?"), url)
        XCTAssertTrue(url.contains("forecast_days=3"), url)
        XCTAssertTrue(url.contains("temperature_unit=fahrenheit"), url)
        XCTAssertTrue(url.contains("timezone=auto"), url)
    }

    func testTheWeatherTextShowsNowAndEachDay() throws {
        let place = Weather.Place(name: "Toronto", admin1: "Ontario", country: "Canada", latitude: 43.7, longitude: -79.4)
        let forecast = data(#"{"current_units":{"temperature_2m":"°C","apparent_temperature":"°C","relative_humidity_2m":"%","wind_speed_10m":"km/h"},"current":{"time":"2026-10-13T07:45","temperature_2m":17.0,"apparent_temperature":17.3,"relative_humidity_2m":94,"weather_code":3,"wind_speed_10m":11.8},"daily_units":{"temperature_2m_max":"°C","temperature_2m_min":"°C","precipitation_probability_max":"%"},"daily":{"time":["2026-10-13","2026-10-14"],"weather_code":[53,3],"temperature_2m_max":[25.6,17.8],"temperature_2m_min":[15.7,10.5],"precipitation_probability_max":[63,8]}}"#)
        let text = try Weather.render(forecast, place: place)
        XCTAssertTrue(text.hasPrefix("Weather for Toronto, Ontario, Canada"), text)
        XCTAssertTrue(text.contains("Now (2026-10-13T07:45): 17 °C, feels like 17.3 °C, overcast, humidity 94%, wind 11.8 km/h"), text)
        XCTAssertTrue(text.contains("- 2026-10-13: moderate drizzle, 15.7 to 25.6 °C, 63% chance of rain or snow"), text)
        XCTAssertTrue(text.contains("Open-Meteo"), text)
    }

    func testWeatherCodesHaveWords() {
        XCTAssertEqual(Weather.describe(code: 0), "clear sky")
        XCTAssertEqual(Weather.describe(code: 95), "thunderstorm")
        XCTAssertEqual(Weather.describe(code: 1234), "weather code 1234")
    }

    // MARK: - Wikipedia

    func testWikipediaAddresses() throws {
        XCTAssertEqual(try Wikipedia.searchURL("swift language", language: "en").absoluteString,
                       "https://en.wikipedia.org/w/rest.php/v1/search/page?q=swift%20language&limit=5")
        XCTAssertEqual(try Wikipedia.pageURL("Swift (programming language)", language: "fr").absoluteString,
                       "https://fr.wikipedia.org/api/rest_v1/page/summary/Swift_(programming_language)")
        XCTAssertThrowsError(try Wikipedia.searchURL("x", language: "evil.com/"))
    }

    func testWikipediaSearchResultsAreListedWithoutMarkup() throws {
        let found = data(#"{"pages":[{"id":1,"key":"Swift_(programming_language)","title":"Swift (programming language)","excerpt":"<span class=\"searchmatch\">Swift</span> is a high-level language &amp; more","description":"General-purpose programming language"}]}"#)
        let text = try Wikipedia.renderSearch(found, query: "swift")
        XCTAssertTrue(text.contains("1. Swift (programming language): General-purpose programming language"), text)
        XCTAssertTrue(text.contains("Swift is a high-level language & more"), text)
        XCTAssertFalse(text.contains("<span"), text)
        XCTAssertEqual(try Wikipedia.renderSearch(data(#"{"pages":[]}"#), query: "zzqq"), #"No Wikipedia pages match "zzqq"."#)
    }

    func testAWikipediaPageShowsItsSummaryAndSource() throws {
        let page = data(#"{"type":"standard","title":"Toronto","description":"Most populous city in Canada","extract":"Toronto is the most populous city in Canada.","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Toronto"}}}"#)
        let text = try Wikipedia.renderPage(page)
        XCTAssertTrue(text.hasPrefix("Toronto: Most populous city in Canada"), text)
        XCTAssertTrue(text.contains("Toronto is the most populous city in Canada."), text)
        XCTAssertTrue(text.contains("Source: https://en.wikipedia.org/wiki/Toronto"), text)
    }

    // MARK: - Dictionary

    func testTheDictionaryListsMeaningsWithExamples() throws {
        XCTAssertEqual(try DictionaryLookup.url("Serendipity").absoluteString, "https://api.dictionaryapi.dev/api/v2/entries/en/serendipity")
        XCTAssertThrowsError(try DictionaryLookup.url("two words?"))
        let entry = data(#"[{"word":"serendipity","phonetic":"/ˌsɛ.ɹən.ˈdɪ.pɪ.ti/","meanings":[{"partOfSpeech":"noun","definitions":[{"definition":"A combination of events which have come together by chance.","example":"a happy serendipity"}],"synonyms":["chance","luck"]}]}]"#)
        let text = try DictionaryLookup.render(entry)
        XCTAssertTrue(text.hasPrefix("serendipity /ˌsɛ.ɹən.ˈdɪ.pɪ.ti/"), text)
        XCTAssertTrue(text.contains("noun\n1. A combination of events which have come together by chance.\n   Example: a happy serendipity"), text)
        XCTAssertTrue(text.contains("Synonyms: chance, luck"), text)
    }

    // MARK: - Currency

    func testExchangeRateAddresses() throws {
        XCTAssertEqual(try CurrencyRates.url(from: "usd", to: "cad, eur", date: nil).absoluteString,
                       "https://api.frankfurter.dev/v1/latest?base=USD&symbols=CAD,EUR")
        XCTAssertEqual(try CurrencyRates.url(from: "EUR", to: nil, date: "2026-01-02").absoluteString,
                       "https://api.frankfurter.dev/v1/2026-01-02?base=EUR")
        XCTAssertThrowsError(try CurrencyRates.url(from: "dollars", to: nil, date: nil))
        XCTAssertThrowsError(try CurrencyRates.url(from: "USD", to: nil, date: "yesterday"))
    }

    func testExchangeRatesAreMultipliedByTheAmount() throws {
        let rates = data(#"{"amount":1.0,"base":"USD","date":"2026-10-12","rates":{"CAD":1.4262,"EUR":0.89437}}"#)
        let text = try CurrencyRates.render(rates, amount: 100)
        XCTAssertTrue(text.contains("on 2026-10-12"), text)
        XCTAssertTrue(text.contains("100 USD = 142.62 CAD"), text)
        XCTAssertTrue(text.contains("100 USD = 89.437 EUR"), text)
    }

    // MARK: - Packages

    func testPackageAddressesForEachRegistry() throws {
        XCTAssertEqual(try PackageInfo.url(registry: "npm", name: "@types/node").absoluteString, "https://registry.npmjs.org/@types/node/latest")
        XCTAssertEqual(try PackageInfo.url(registry: "pip", name: "requests").absoluteString, "https://pypi.org/pypi/requests/json")
        XCTAssertEqual(try PackageInfo.url(registry: "cargo", name: "serde").absoluteString, "https://crates.io/api/v1/crates/serde")
        XCTAssertEqual(try PackageInfo.url(registry: "go", name: "github.com/BurntSushi/toml").absoluteString,
                       "https://proxy.golang.org/github.com/!burnt!sushi/toml/@latest")
        XCTAssertThrowsError(try PackageInfo.url(registry: "maven", name: "x"))
        XCTAssertThrowsError(try PackageInfo.url(registry: "npm", name: "../../etc"))
    }

    func testAnNpmPackageShowsItsVersionAndRepository() throws {
        let latest = data(#"{"name":"react","version":"19.3.0","description":"React is a JavaScript library.","license":"MIT","homepage":"https://react.dev/","repository":{"url":"git+https://github.com/react/react.git","type":"git"}}"#)
        let text = try PackageInfo.render(registry: "npm", data: latest)
        XCTAssertTrue(text.hasPrefix("npm package react"), text)
        XCTAssertTrue(text.contains("Latest version: 19.3.0"), text)
        XCTAssertTrue(text.contains("Repository: https://github.com/react/react"), text)
        XCTAssertFalse(text.contains("git+"), text)
    }

    func testPyPICratesAndGoPackagesShowTheirVersions() throws {
        let pypi = data(#"{"info":{"name":"requests","version":"2.34.2","summary":"Python HTTP for Humans.","license":"Apache-2.0","requires_python":">=3.10","project_urls":{"Source":"https://github.com/psf/requests"}},"urls":[{"upload_time_iso_8601":"2026-05-14T19:25:26.443000Z"}]}"#)
        let pypiText = try PackageInfo.render(registry: "pypi", data: pypi)
        XCTAssertTrue(pypiText.contains("Latest version: 2.34.2"), pypiText)
        XCTAssertTrue(pypiText.contains("Released: 2026-05-14"), pypiText)
        XCTAssertTrue(pypiText.contains("Python: >=3.10"), pypiText)

        let crate = data(#"{"crate":{"name":"serde","max_stable_version":"1.0.229","newest_version":"1.0.229","description":"A serialization framework","repository":"https://github.com/serde-rs/serde","downloads":1520690013,"updated_at":"2026-07-18T23:05:13Z"}}"#)
        XCTAssertTrue(try PackageInfo.render(registry: "crates", data: crate).contains("Latest version: 1.0.229"))

        let module = data(#"{"Version":"v1.12.0","Time":"2026-02-28T10:10:09Z","Origin":{"URL":"https://github.com/gin-gonic/gin"}}"#)
        let goText = try PackageInfo.render(registry: "go", data: module)
        XCTAssertTrue(goText.contains("Latest version: v1.12.0"), goText)
        XCTAssertTrue(goText.contains("Released: 2026-02-28"), goText)
    }

    // MARK: - Stack Overflow

    func testStackOverflowAddresses() throws {
        let search = try StackOverflow.searchURL("swift async let").absoluteString
        XCTAssertTrue(search.hasPrefix("https://api.stackexchange.com/2.3/search/advanced?"), search)
        XCTAssertTrue(search.contains("q=swift%20async%20let"), search)
        XCTAssertTrue(search.contains("site=stackoverflow"), search)
        XCTAssertTrue(try StackOverflow.answersURL("26567419").absoluteString.contains("/questions/26567419/answers?"))
        XCTAssertThrowsError(try StackOverflow.answersURL("12; drop"))
    }

    func testStackOverflowSearchResultsAreListed() throws {
        let found = data(#"{"items":[{"tags":["swift","async-await"],"is_answered":true,"accepted_answer_id":5,"answer_count":1,"score":3,"question_id":68900512,"link":"https://stackoverflow.com/questions/68900512/x","title":"Can&#39;t cancel an async let"}],"quota_remaining":296}"#)
        let text = try StackOverflow.renderSearch(found, query: "async let")
        XCTAssertTrue(text.contains("1. Can't cancel an async let (question 68900512)"), text)
        XCTAssertTrue(text.contains("score 3, 1 answer, accepted answer"), text)
        XCTAssertTrue(text.contains("tags: swift, async-await"), text)
    }

    func testStackOverflowAnswersKeepTheirCode() throws {
        let answers = data(#"{"items":[{"is_accepted":true,"score":7,"answer_id":1,"body":"<p>Use <code>Task</code>:</p>\n<pre><code>let t = Task { await work() }\nt.cancel() &amp;&amp; done\n</code></pre>\n<p>That&#39;s it.</p>"}]}"#)
        let text = try StackOverflow.renderAnswers(answers, questionID: "26567419")
        XCTAssertTrue(text.contains("## Answer 1 (score 7, accepted)"), text)
        XCTAssertTrue(text.contains("Use `Task`:"), text)
        XCTAssertTrue(text.contains("```\nlet t = Task { await work() }\nt.cancel() && done\n```"), text)
        XCTAssertTrue(text.contains("That's it."), text)
        XCTAssertTrue(text.contains("https://stackoverflow.com/q/26567419"), text)
    }

    func testAStackExchangeErrorIsShown() {
        XCTAssertThrowsError(try StackOverflow.renderSearch(data(#"{"error_id":502,"error_message":"too many requests from this IP","error_name":"throttle_violation"}"#), query: "x")) { error in
            XCTAssertTrue(error.localizedDescription.contains("too many requests"), error.localizedDescription)
        }
    }

    // MARK: - Public GitHub repos

    func testRepoNamesAreReadFromNamesAndLinks() throws {
        XCTAssertEqual(try PublicGitHub.repoPath("LAOUUUUU/Gatita"), "LAOUUUUU/Gatita")
        XCTAssertEqual(try PublicGitHub.repoPath("https://github.com/apple/swift.git"), "apple/swift")
        XCTAssertThrowsError(try PublicGitHub.repoPath("not a repo"))
        XCTAssertThrowsError(try PublicGitHub.repoPath("a/b/../c"))
    }

    func testARepoShowsItsFactsAndNewestRelease() throws {
        let repo = data(#"{"full_name":"LAOUUUUU/Gatita","description":"SwiftUI chat app","stargazers_count":4,"forks_count":1,"open_issues_count":2,"language":"Swift","license":{"spdx_id":"MIT"},"default_branch":"main","pushed_at":"2026-10-10T02:44:12Z","html_url":"https://github.com/LAOUUUUU/Gatita","homepage":null,"archived":false}"#)
        let releases = data(#"[{"tag_name":"v0.0.5-alpha","name":"Gatita 0.0.5 alpha","published_at":"2026-10-10T02:44:18Z","prerelease":true}]"#)
        let text = try PublicGitHub.renderRepo(repo, releases: releases)
        XCTAssertTrue(text.hasPrefix("LAOUUUUU/Gatita: SwiftUI chat app"), text)
        XCTAssertTrue(text.contains("Stars: 4 · Forks: 1 · Open issues: 2"), text)
        XCTAssertTrue(text.contains("Newest release: v0.0.5-alpha (Gatita 0.0.5 alpha), a pre-release, published 2026-10-10"), text)
        XCTAssertTrue(text.contains("License: MIT"), text)
    }

    // MARK: - Shared text helpers

    func testHTMLEntitiesAreDecoded() {
        XCTAssertEqual(PublicAPI.decodeEntities("a &amp; b &lt;c&gt; &#39;d&#39; &#x41; &quot;e&quot;"), "a & b <c> 'd' A \"e\"")
    }
}
