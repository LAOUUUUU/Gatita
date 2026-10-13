//
//  InfoConnectors.swift
//  Gatita
//

import Foundation

/// Current weather and a daily forecast from Open-Meteo (open-meteo.com). Free for non-commercial use, no key.
/// The place is found by name with Open-Meteo's geocoding first.
nonisolated enum Weather {
    struct Place: Equatable, Sendable {
        let name: String
        let admin1: String?
        let country: String?
        let latitude: Double
        let longitude: Double

        var label: String {
            ([name, admin1, country].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: ", ")
        }
    }

    /// The geocoding address. Only the part before the first comma is the name; the rest picks among the results.
    static func geocodeURL(place: String) throws -> URL {
        let name = place.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !name.isEmpty else { throw ToolError("give a place, such as \"Toronto\" or \"Paris, France\"") }
        return try PublicAPI.url("https://geocoding-api.open-meteo.com/v1/search",
                                 query: [("name", name), ("count", "10"), ("language", "en"), ("format", "json")])
    }

    /// The result that matches the region or country after the comma, if one was given, or else the first result.
    static func pickPlace(_ data: Data, query: String) throws -> Place {
        let results = (PublicAPI.object(data)?["results"] as? [[String: Any]]) ?? []
        let places: [(place: Place, code: String)] = results.compactMap { result in
            guard let name = result["name"] as? String,
                  let latitude = PublicAPI.double(result["latitude"]),
                  let longitude = PublicAPI.double(result["longitude"]) else { return nil }
            return (Place(name: name, admin1: result["admin1"] as? String, country: result["country"] as? String,
                          latitude: latitude, longitude: longitude),
                    (result["country_code"] as? String) ?? "")
        }
        guard let first = places.first else {
            throw ToolError("no place called \(query) was found. Try the city name alone, or a bigger city nearby.")
        }
        let parts = query.split(separator: ",").dropFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !parts.isEmpty else { return first.place }
        let match = places.first { entry in
            let fields = [entry.place.admin1, entry.place.country, entry.code].compactMap { $0?.lowercased() }
            return parts.allSatisfy { part in fields.contains { $0 == part || $0.hasPrefix(part) } }
        }
        return (match ?? first).place
    }

    static func forecastURL(_ place: Place, days: Int, imperial: Bool) -> URL {
        var query = [
            ("latitude", PublicAPI.number(place.latitude)), ("longitude", PublicAPI.number(place.longitude)),
            ("current", "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            ("daily", "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            ("timezone", "auto"), ("forecast_days", String(min(max(days, 1), 7))),
        ]
        if imperial {
            query += [("temperature_unit", "fahrenheit"), ("wind_speed_unit", "mph")]
        }
        // The parts are fixed and valid, so building the address cannot fail.
        return (try? PublicAPI.url("https://api.open-meteo.com/v1/forecast", query: query))!
    }

    static func render(_ data: Data, place: Place) throws -> String {
        let object = try PublicAPI.requireObject(data, service: "Open-Meteo")
        var lines = ["Weather for \(place.label) (\(PublicAPI.number(place.latitude, digits: 2)), \(PublicAPI.number(place.longitude, digits: 2)))"]

        if let current = object["current"] as? [String: Any] {
            let units = (object["current_units"] as? [String: Any]) ?? [:]
            var parts: [String] = []
            if let value = PublicAPI.double(current["temperature_2m"]) { parts.append(measure(value, units["temperature_2m"])) }
            if let value = PublicAPI.double(current["apparent_temperature"]) {
                parts.append("feels like " + measure(value, units["apparent_temperature"]))
            }
            if let code = PublicAPI.double(current["weather_code"]) { parts.append(describe(code: Int(code))) }
            if let value = PublicAPI.double(current["relative_humidity_2m"]) {
                parts.append("humidity " + measure(value, units["relative_humidity_2m"]))
            }
            if let value = PublicAPI.double(current["wind_speed_10m"]) { parts.append("wind " + measure(value, units["wind_speed_10m"])) }
            let time = (current["time"] as? String).map { " (\($0))" } ?? ""
            lines.append("Now\(time): " + parts.joined(separator: ", "))
        }

        if let daily = object["daily"] as? [String: Any], let days = daily["time"] as? [String] {
            let units = (object["daily_units"] as? [String: Any]) ?? [:]
            let codes = daily["weather_code"] as? [Any] ?? []
            let highs = daily["temperature_2m_max"] as? [Any] ?? []
            let lows = daily["temperature_2m_min"] as? [Any] ?? []
            let rain = daily["precipitation_probability_max"] as? [Any] ?? []
            lines.append("Forecast:")
            for (index, day) in days.enumerated() {
                var parts: [String] = []
                if index < codes.count, let code = PublicAPI.double(codes[index]) { parts.append(describe(code: Int(code))) }
                if index < lows.count, index < highs.count,
                   let low = PublicAPI.double(lows[index]), let high = PublicAPI.double(highs[index]) {
                    parts.append("\(PublicAPI.number(low, digits: 1)) to " + measure(high, units["temperature_2m_max"]))
                }
                if index < rain.count, let chance = PublicAPI.double(rain[index]) {
                    parts.append(measure(chance, units["precipitation_probability_max"]) + " chance of rain or snow")
                }
                lines.append("- \(day): " + parts.joined(separator: ", "))
            }
        }
        lines.append("Source: Open-Meteo (open-meteo.com)")
        return lines.joined(separator: "\n")
    }

    /// "17 °C", "94%": a value and its unit, with no space before a percent sign.
    private static func measure(_ value: Double, _ unit: Any?) -> String {
        let unit = (unit as? String) ?? ""
        let number = PublicAPI.number(value, digits: 1)
        return unit.isEmpty ? number : unit == "%" ? number + "%" : "\(number) \(unit)"
    }

    /// The words for a WMO weather code, as Open-Meteo's documentation lists them.
    static func describe(code: Int) -> String {
        let words: [Int: String] = [
            0: "clear sky", 1: "mainly clear", 2: "partly cloudy", 3: "overcast", 45: "fog", 48: "depositing rime fog",
            51: "light drizzle", 53: "moderate drizzle", 55: "dense drizzle", 56: "light freezing drizzle",
            57: "dense freezing drizzle", 61: "slight rain", 63: "moderate rain", 65: "heavy rain",
            66: "light freezing rain", 67: "heavy freezing rain", 71: "slight snowfall", 73: "moderate snowfall",
            75: "heavy snowfall", 77: "snow grains", 80: "slight rain showers", 81: "moderate rain showers",
            82: "violent rain showers", 85: "slight snow showers", 86: "heavy snow showers", 95: "thunderstorm",
            96: "thunderstorm with slight hail", 97: "heavy thunderstorm", 99: "thunderstorm with heavy hail",
        ]
        return words[code] ?? "weather code \(code)"
    }

    static func run(_ arguments: [String: String]) async throws -> String {
        let query = arguments["place"] ?? arguments["city"] ?? arguments["location"] ?? ""
        let found = try await PublicAPI.getOK(try geocodeURL(place: query), service: "Open-Meteo")
        let place = try pickPlace(found, query: query)
        let days = Int(arguments["days"] ?? "") ?? 3
        let units = (arguments["units"] ?? "").lowercased()
        let imperial = units.hasPrefix("imp") || units.hasPrefix("fahr") || units == "us"
        let forecast = try await PublicAPI.getOK(forecastURL(place, days: days, imperial: imperial), service: "Open-Meteo")
        return try render(forecast, place: place)
    }
}

/// Wikipedia search and page summaries, through the Wikimedia REST APIs. No key; Wikimedia asks for a
/// User-Agent that names the app, which PublicAPI sends.
nonisolated enum Wikipedia {
    private static func host(_ language: String) throws -> String {
        let code = language.trimmingCharacters(in: .whitespaces).lowercased()
        guard code.range(of: #"^[a-z]{2,3}(-[a-z]{2,8})?$"#, options: .regularExpression) != nil else {
            throw ToolError("language must be a Wikipedia language code such as en, fr, or es")
        }
        return "https://\(code).wikipedia.org"
    }

    static func searchURL(_ query: String, language: String) throws -> URL {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ToolError("give something to search for") }
        return try PublicAPI.url(try host(language), path: "/w/rest.php/v1/search/page", query: [("q", text), ("limit", "5")])
    }

    static func pageURL(_ title: String, language: String) throws -> URL {
        let key = title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else { throw ToolError("give the page title") }
        return try PublicAPI.url(try host(language), path: "/api/rest_v1/page/summary/" + PublicAPI.pathSegment(key))
    }

    static func renderSearch(_ data: Data, query: String) throws -> String {
        let pages = (try PublicAPI.requireObject(data, service: "Wikipedia")["pages"] as? [[String: Any]]) ?? []
        guard !pages.isEmpty else { return "No Wikipedia pages match \"\(query)\"." }
        var lines = ["Wikipedia pages for \"\(query)\":"]
        for (index, page) in pages.enumerated() {
            let title = (page["title"] as? String) ?? "?"
            let description = (page["description"] as? String).map { ": " + $0 } ?? ""
            lines.append("\(index + 1). \(title)\(description)")
            if let excerpt = page["excerpt"] as? String {
                lines.append("   " + PublicAPI.stripTags(excerpt))
            }
            if let key = page["key"] as? String {
                lines.append("   title: \(key)")
            }
        }
        lines.append("Read one with wikipedia_page and its title.")
        return lines.joined(separator: "\n")
    }

    static func renderPage(_ data: Data) throws -> String {
        let page = try PublicAPI.requireObject(data, service: "Wikipedia")
        let title = (page["title"] as? String) ?? "?"
        let description = (page["description"] as? String).map { ": " + $0 } ?? ""
        var parts = [title + description]
        if page["type"] as? String == "disambiguation" {
            parts.append("This title has several meanings. Search with wikipedia_search for the one you need.")
        }
        if let extract = page["extract"] as? String, !extract.isEmpty {
            parts.append(extract)
        }
        let address = ((page["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
        parts.append("Source: \(address ?? "Wikipedia") (Wikipedia, CC BY-SA 4.0)")
        return parts.joined(separator: "\n\n")
    }

    static func run(_ tool: String, arguments: [String: String]) async throws -> String {
        let language = arguments["language"] ?? arguments["lang"] ?? "en"
        if tool == "wikipedia_search" {
            let query = arguments["query"] ?? ""
            return try renderSearch(try await PublicAPI.getOK(try searchURL(query, language: language), service: "Wikipedia"),
                                    query: query)
        }
        let title = arguments["title"] ?? ""
        let data = try await PublicAPI.getOK(try pageURL(title, language: language), service: "Wikipedia",
                                             notFound: "no Wikipedia page is titled \(title). Find the title with wikipedia_search.")
        return try renderPage(data)
    }
}

/// English definitions from the Free Dictionary API (dictionaryapi.dev). No key.
nonisolated enum DictionaryLookup {
    static func url(_ word: String) throws -> URL {
        let text = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count <= 60,
              text.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else {
            throw ToolError("give one English word or short phrase, letters only")
        }
        return try PublicAPI.url("https://api.dictionaryapi.dev/api/v2/entries/en/" + PublicAPI.pathSegment(text))
    }

    static func render(_ data: Data) throws -> String {
        guard let entries = PublicAPI.array(data) as? [[String: Any]], let first = entries.first else {
            throw ToolError("no definition was found")
        }
        let word = (first["word"] as? String) ?? ""
        let phonetic = entries.lazy.compactMap { entry -> String? in
            if let text = entry["phonetic"] as? String, !text.isEmpty { return text }
            return (entry["phonetics"] as? [[String: Any]])?.lazy.compactMap { $0["text"] as? String }.first { !$0.isEmpty }
        }.first
        var sections = [phonetic.map { "\(word) \($0)" } ?? word]

        // Meanings from every entry, grouped by part of speech in the order they first appear.
        var order: [String] = []
        var definitions: [String: [[String: Any]]] = [:]
        var synonyms: [String: [String]] = [:]
        for entry in entries {
            for meaning in (entry["meanings"] as? [[String: Any]]) ?? [] {
                let part = (meaning["partOfSpeech"] as? String) ?? "other"
                if definitions[part] == nil { order.append(part) }
                definitions[part, default: []] += (meaning["definitions"] as? [[String: Any]]) ?? []
                synonyms[part, default: []] += (meaning["synonyms"] as? [String]) ?? []
            }
        }
        for part in order {
            var lines = [part]
            for (index, definition) in (definitions[part] ?? []).prefix(4).enumerated() {
                lines.append("\(index + 1). \((definition["definition"] as? String) ?? "")")
                if let example = definition["example"] as? String, !example.isEmpty {
                    lines.append("   Example: \(example)")
                }
            }
            var seen = Set<String>()
            let words = (synonyms[part] ?? []).filter { seen.insert($0).inserted }.prefix(6)
            if !words.isEmpty {
                lines.append("Synonyms: " + words.joined(separator: ", "))
            }
            sections.append(lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    static func run(_ arguments: [String: String]) async throws -> String {
        let word = arguments["word"] ?? ""
        let (data, status) = try await PublicAPI.get(try url(word))
        guard (200..<300).contains(status) else {
            throw ToolError(status == 404 ? "no definition was found for \(word)" : "the dictionary answered HTTP \(status)")
        }
        return try render(data)
    }
}

/// Daily exchange rates from Frankfurter (frankfurter.dev), which publishes the European Central Bank's
/// reference rates. No key.
nonisolated enum CurrencyRates {
    private static func code(_ text: String) throws -> String {
        let code = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw ToolError("\(text) is not a currency code. Use three letters, such as USD, CAD, or EUR.")
        }
        return code
    }

    static func url(from: String, to: String?, date: String?) throws -> URL {
        let base = try code(from)
        let targets = try (to ?? "").split(whereSeparator: { $0 == "," || $0 == " " }).map { try code(String($0)) }
        var day = (date ?? "").trimmingCharacters(in: .whitespaces)
        if day.isEmpty || day.lowercased() == "latest" {
            day = "latest"
        } else if day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
            throw ToolError("date must look like 2026-01-31")
        }
        var query = [("base", base)]
        if !targets.isEmpty { query.append(("symbols", targets.joined(separator: ","))) }
        return try PublicAPI.url("https://api.frankfurter.dev/v1/" + day, query: query)
    }

    static func render(_ data: Data, amount: Double) throws -> String {
        let object = try PublicAPI.requireObject(data, service: "Frankfurter")
        guard let base = object["base"] as? String, let rates = object["rates"] as? [String: Any] else {
            throw ToolError(PublicAPI.reason(in: data) ?? "no rates came back")
        }
        let day = (object["date"] as? String) ?? "?"
        var lines = ["Exchange rates on \(day) (European Central Bank reference rates, via frankfurter.dev):"]
        for (target, value) in rates.sorted(by: { $0.key < $1.key }) {
            guard let rate = PublicAPI.double(value) else { continue }
            lines.append("\(PublicAPI.number(amount)) \(base) = \(PublicAPI.number(amount * rate)) \(target)")
        }
        return lines.joined(separator: "\n")
    }

    static func run(_ arguments: [String: String]) async throws -> String {
        let amount = Double(arguments["amount"] ?? "") ?? 1
        guard amount > 0 else { throw ToolError("amount must be more than zero") }
        let address = try url(from: arguments["from"] ?? arguments["base"] ?? "", to: arguments["to"], date: arguments["date"])
        let data = try await PublicAPI.getOK(address, service: "Frankfurter",
                                             notFound: "unknown currency code, or no rates for that day. Rates exist for about 30 major currencies.")
        return try render(data, amount: amount)
    }
}
