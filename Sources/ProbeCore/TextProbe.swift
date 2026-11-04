import Foundation

/// Text, encoding and date probes. All strings are synthetic.
public enum TextProbe {

    // MARK: - Regex and UTF-16 ranges

    public static func regexChinese() -> ProbeResult {
        let haystack = "这是样例文本，包含样例与文档两个词。"
        var details: [String: String] = ["haystackLength": "\(haystack.count)"]
        do {
            let expression = try NSRegularExpression(pattern: "样例", options: [])
            let utf16 = haystack as NSString
            let matches = expression.matches(
                in: haystack, options: [], range: NSRange(location: 0, length: utf16.length))

            let ranges = matches.map { "\($0.range.location):\($0.range.length)" }
            details["matchCount"] = "\(matches.count)"
            details["utf16Ranges"] = ranges.joined(separator: ",")
            details["utf16Length"] = "\(utf16.length)"

            // Locating a match through a String.Index must agree with NSString.
            let first = (haystack as NSString).substring(with: matches.first?.range ?? NSRange(location: 0, length: 0))
            details["substringOfFirstMatch"] = first

            let ok = matches.count == 2 && first == "样例"
            return ProbeResult(name: "text.regexChinese", ok: ok, details: details)
        } catch {
            ProbeLog.recordError("text.regexChinese", error)
            details["result"] = "regex-compile-failed"
            return ProbeResult(name: "text.regexChinese", ok: false, details: details)
        }
    }

    public static func regexUnicodeProperty() -> ProbeResult {
        let haystack = "abc 中文 123"
        var details: [String: String] = [:]
        do {
            // ICU script property; unsupported engines throw at compile time.
            let expression = try NSRegularExpression(pattern: "\\p{Script=Han}+", options: [])
            let range = NSRange(location: 0, length: (haystack as NSString).length)
            let hits = expression.matches(in: haystack, options: [], range: range)
            details["hanSequenceCount"] = "\(hits.count)"
            details["range"] = hits.first.map { "\($0.range.location):\($0.range.length)" } ?? "none"
            return ProbeResult(name: "text.regexUnicodeProperty", ok: hits.count == 1, details: details)
        } catch {
            ProbeLog.recordError("text.regexUnicodeProperty", error)
            details["result"] = "script-property-unsupported"
            return ProbeResult(name: "text.regexUnicodeProperty", ok: false, details: details)
        }
    }

    // MARK: - Unicode normalisation

    public static func normalisation() -> ProbeResult {
        let decomposed = "cafe\u{0301}"
        let precomposed = "caf\u{00E9}"
        let toNFC = decomposed.precomposedStringWithCanonicalMapping
        let toNFD = precomposed.decomposedStringWithCanonicalMapping

        var details: [String: String] = [
            "decomposedScalars": "\(decomposed.unicodeScalars.count)",
            "precomposedScalars": "\(precomposed.unicodeScalars.count)",
            "decomposedToNFC": toNFC,
            "precomposedToNFD": toNFD,
            "nfdScalars": "\(toNFD.unicodeScalars.count)"
        ]

        // Optional: folding is used for comparison-style lookups.
        let folded = "Café".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        details["folded"] = folded

        let numeric = "a2".compare("a10", options: .numeric)
        details["numericCompareA2vsA10"] = "\(numeric.rawValue)"

        // Invariant: NFC(NFD(x)) and NFD(NFC(x)) converge on equal strings.
        let ok = toNFC == precomposed && toNFD == decomposed
        return ProbeResult(name: "text.normalisation", ok: ok, details: details)
    }

    public static func characterSets() -> ProbeResult {
        let text = "alpha\u{00A0}beta gamma\n\tdelta"
        let pieces = text.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let scalarsRemoved = text.unicodeScalars.filter {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }.count

        let details: [String: String] = [
            "pieces": pieces.joined(separator: ","),
            "pieceCount": "\(pieces.count)",
            "whitespaceScalarCount": "\(scalarsRemoved)",
            "containsNBSP": "\(CharacterSet.whitespacesAndNewlines.contains("\u{00A0}"))"
        ]
        return ProbeResult(name: "text.characterSets", ok: pieces.count == 4, details: details)
    }

    // MARK: - Dates

    public static func dateFormatting() -> ProbeResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let rendered = formatter.string(from: instant)
        let parsed = formatter.date(from: rendered)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: instant)

        let iso = ISO8601DateFormatter()
        let isoText = iso.string(from: instant)
        let isoParsed = iso.date(from: isoText)

        let details: [String: String] = [
            "formatted": rendered,
            "parsedBackEquals": "\(parsed == instant)",
            "parsedDescription": parsed.map { "\($0.timeIntervalSince1970)" } ?? "nil",
            "components": "\(components.year ?? -1)-\(components.month ?? -1)-\(components.day ?? -1) \(components.hour ?? -1)",
            "iso8601": isoText,
            "isoParsedEquals": "\(isoParsed == instant)"
        ]
        let ok = rendered == "2023-11-14 22:13:20" && parsed == instant && isoParsed == instant
        return ProbeResult(name: "text.dateFormatting", ok: ok, details: details)
    }

    // MARK: - JSON

    public struct Item: Codable, Equatable {
        public let id: Int
        public let title: String
        public let tags: [String]

        public init(id: Int, title: String, tags: [String]) {
            self.id = id
            self.title = title
            self.tags = tags
        }
    }

    public static func jsonRoundTrip() -> ProbeResult {
        let original = Item(id: 1, title: "样例文档", tags: ["样例", "文本"])
        var details: [String: String] = [:]
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(original)
            let decoder = JSONDecoder()
            let restored = try decoder.decode(Item.self, from: data)

            details["json"] = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            details["byteCount"] = "\(data.count)"
            details["roundTripEqual"] = "\(restored == original)"
            return ProbeResult(name: "text.jsonRoundTrip", ok: restored == original, details: details)
        } catch {
            ProbeLog.recordError("text.jsonRoundTrip", error)
            return ProbeResult(name: "text.jsonRoundTrip", ok: false)
        }
    }

    // MARK: - String search helpers used by the app

    public static func stringSearch() -> ProbeResult {
        let haystack = "alpha-beta-gamma"
        let found = haystack.range(of: "beta")
        let caseless = haystack.range(of: "BETA", options: [.caseInsensitive])
        let fromIndex = found.map { haystack.distance(from: haystack.startIndex, to: $0.lowerBound) } ?? -1

        let details: [String: String] = [
            "foundLocation": "\(fromIndex)",
            "caselessFound": "\(caseless != nil)",
            "containsChinese": "\(("样例文档".contains("样例")))"
        ]
        return ProbeResult(name: "text.stringSearch", ok: fromIndex == 6 && caseless != nil, details: details)
    }
}
