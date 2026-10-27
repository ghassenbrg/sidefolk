import Foundation
import SidefolkExtensionKit

/// The European Central Bank's reference rates: the euro against 30 major currencies, published each working day
/// around 16:00 CET. Free, official, and nothing about the person is sent: the same file for everyone.
@MainActor
enum Rates {
    static let address = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static var cache: String { Paths.data + "/ecb-rates.json" }

    struct Table {
        var day: String
        /// Units of each currency per euro; EUR itself is 1.
        var perEuro: [String: Double]
    }

    /// Words people use for the currencies the ECB lists.
    static let names: [String: String] = [
        "dollar": "USD", "dollars": "USD", "us dollar": "USD", "us dollars": "USD", "$": "USD", "euro": "EUR", "euros": "EUR", "€": "EUR",
        "yen": "JPY", "¥": "JPY", "pound": "GBP", "pounds": "GBP", "sterling": "GBP", "£": "GBP", "yuan": "CNY", "renminbi": "CNY",
        "rmb": "CNY", "won": "KRW", "swiss franc": "CHF", "swiss francs": "CHF", "franc": "CHF", "francs": "CHF", "rupee": "INR",
        "rupees": "INR", "real": "BRL", "reais": "BRL", "canadian dollar": "CAD", "canadian dollars": "CAD", "australian dollar": "AUD",
        "australian dollars": "AUD", "new zealand dollar": "NZD", "hong kong dollar": "HKD", "singapore dollar": "SGD", "peso": "MXN",
        "pesos": "MXN", "mexican peso": "MXN", "rand": "ZAR", "lira": "TRY", "zloty": "PLN", "krona": "SEK", "kronor": "SEK",
        "krone": "NOK", "kroner": "NOK", "danish krone": "DKK", "forint": "HUF", "koruna": "CZK", "leu": "RON", "lev": "BGN",
        "shekel": "ILS", "shekels": "ILS", "baht": "THB", "ringgit": "MYR", "rupiah": "IDR", "philippine peso": "PHP", "krona iceland": "ISK",
    ]

    static func code(_ raw: String, in table: Table) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let code = names[text.lowercased()] ?? text.uppercased()
        guard table.perEuro[code] != nil else {
            throw Problem("The ECB doesn't publish a rate for “\(text)”. It covers EUR and \(table.perEuro.keys.filter { $0 != "EUR" }.sorted().joined(separator: ", ")).")
        }
        return code
    }

    /// Today's table, from the cache when it was fetched in the last six hours.
    static func table(now: Date = Date()) async throws -> Table {
        if let data = FileManager.default.contents(atPath: cache),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let fetched = saved["fetched"] as? Double,
           now.timeIntervalSince1970 - fetched < 6 * 3600, let day = saved["day"] as? String, let rates = saved["rates"] as? [String: Double] {
            return Table(day: day, perEuro: rates)
        }
        let table = try parse(String(decoding: try await Web.data(address), as: UTF8.self))
        let saved: [String: Any] = ["fetched": now.timeIntervalSince1970, "day": table.day, "rates": table.perEuro]
        if let data = try? JSONSerialization.data(withJSONObject: saved) { FileManager.default.createFile(atPath: cache, contents: data) }
        return table
    }

    /// `<Cube time='2026-10-27'>` then `<Cube currency='USD' rate='1.0812'/>` lines.
    nonisolated static func parse(_ xml: String) throws -> Table {
        guard let day = xml.firstMatch(of: /time=['"](\d{4}-\d{2}-\d{2})['"]/)?.1 else { throw Problem("The ECB's rates file had no date.") }
        var rates = ["EUR": 1.0]
        for m in xml.matches(of: /currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/) { rates[String(m.1)] = Double(m.2) }
        guard rates.count > 1 else { throw Problem("The ECB's rates file had no rates.") }
        return Table(day: String(day), perEuro: rates)
    }

    nonisolated static func rate(_ from: String, _ to: String, in table: Table) -> Double {
        table.perEuro[to]! / table.perEuro[from]!
    }

    nonisolated static func money(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
    }

    /// A rate keeps more digits than an amount: 1 USD = 0.8969 EUR.
    nonisolated static func rateText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(abs(value) >= 100 ? 0...2 : 2...4)).locale(Locale(identifier: "en_US")))
    }

    static func convert(_ amount: Double, from: String, to: [String]) async throws -> String {
        let table = try await table()
        let source = try code(from, in: table)
        var lines: [String] = []
        for target in to {
            let code = try code(target, in: table)
            let rate = rate(source, code, in: table)
            lines.append("\(money(amount)) \(source) = \(money(amount * rate)) \(code) (1 \(source) = \(rateText(rate)) \(code))")
        }
        return lines.joined(separator: "\n") + "\nECB reference rates of \(table.day)."
    }

    /// Tells once when the rate goes above (or below) a line, and again only after it came back.
    static func crosses(_ settings: Arguments, state: [String: Any]) async throws -> Check {
        let table = try await table()
        let from = try code(try settings.required("from"), in: table), to = try code(try settings.required("to"), in: table)
        let rate = rate(from, to, in: table)
        let line: Double, above: Bool
        if let a = settings.double("above") { (line, above) = (a, true) } else if let b = settings.double("below") { (line, above) = (b, false) } else {
            throw Problem("Give “above” or “below”: the rate to watch for.")
        }
        let past = above ? rate > line : rate < line
        let summary = "1 \(from) = \(rateText(rate)) \(to) (ECB, \(table.day))" + (past ? ", \(above ? "above" : "below") \(rateText(line))." : ".")
        return Check(triggered: past && state["past"] as? Bool != true, state: ["past": past], summary: summary)
    }
}
