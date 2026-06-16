import Foundation

enum XMLTVParser {
    static func parse(_ text: String) -> [EPGProgram] {
        let pattern = #"<programme\b([^>]*)>(.*?)</programme>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let attributeRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text) else {
                return nil
            }

            let attributes = attributes(from: String(text[attributeRange]))
            guard let channelId = attributes["channel"],
                  let start = attributes["start"],
                  let stop = attributes["stop"],
                  let title = title(from: String(text[bodyRange])),
                  let startAt = parseDate(start),
                  let endAt = parseDate(stop) else {
                return nil
            }

            return EPGProgram(
                channelId: channelId,
                title: decodeEntities(title),
                startAt: startAt,
                endAt: endAt
            )
        }
    }

    // MARK: - Cached static resources (compiled/allocated once for the lifetime of the app)

    /// Compiled once — was previously re-compiled for every <programme> attribute block.
    private static let attributeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"([\w-]+)\s*=\s*"([^"]*)""#
    )

    /// Compiled once — was previously re-compiled for every <programme> body block.
    private static let titleRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"<title\b[^>]*>(.*?)</title>"#,
        options: [.dotMatchesLineSeparators]
    )

    /// Shared formatter for timestamps with timezone offset (e.g. "20240101120000 +0000").
    /// DateFormatter is expensive to initialize; sharing one saves 100k+ allocations per EPG import.
    private static let dateFormatterWithZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    /// Shared formatter for bare timestamps without timezone (e.g. "20240101120000").
    private static let dateFormatterNoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    private static func attributes(from text: String) -> [String: String] {
        guard let regex = attributeRegex else { return [:] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else {
                return
            }

            result[String(text[keyRange])] = String(text[valueRange])
        }
    }

    private static func title(from text: String) -> String? {
        guard let regex = titleRegex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges == 2,
              let titleRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[titleRange])
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = dateFormatterWithZone.date(from: value) {
            return date
        }
        return dateFormatterNoZone.date(from: String(value.prefix(14)))
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
