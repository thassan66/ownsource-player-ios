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

    private static func attributes(from text: String) -> [String: String] {
        let pattern = #"([\w-]+)\s*=\s*"([^"]*)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [:]
        }

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
        let pattern = #"<title\b[^>]*>(.*?)</title>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges == 2,
              let titleRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[titleRange])
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss Z"

        if let date = formatter.date(from: value) {
            return date
        }

        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: String(value.prefix(14)))
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
