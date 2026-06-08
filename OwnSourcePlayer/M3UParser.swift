import Foundation

struct ParsedChannel {
    var name: String
    var streamURL: String
    var category: String
    var logoURL: String?
    var tvgId: String?
}

enum M3UParser {
    private static let attributeRegex = try? NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)

    static func parse(_ text: String) -> [ParsedChannel] {
        var channels: [ParsedChannel] = []
        var pendingInfo: [String: String] = [:]
        var pendingName: String?

        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                return
            }

            if line.hasPrefix("#EXTINF") {
                pendingInfo = attributes(from: line)
                pendingName = displayName(from: line)
                return
            }

            if line.hasPrefix("#") {
                return
            }

            guard line.lowercased().hasPrefix("http") else {
                return
            }

            let channel = ParsedChannel(
                name: pendingName ?? pendingInfo["tvg-name"] ?? line,
                streamURL: line,
                category: pendingInfo["group-title"] ?? "Uncategorized",
                logoURL: pendingInfo["tvg-logo"],
                tvgId: pendingInfo["tvg-id"]
            )
            channels.append(channel)
            pendingInfo = [:]
            pendingName = nil
        }

        return channels
    }

    private static func displayName(from line: String) -> String? {
        guard let commaIndex = line.lastIndex(of: ",") else {
            return nil
        }

        let name = line[line.index(after: commaIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func attributes(from line: String) -> [String: String] {
        var result: [String: String] = [:]

        guard let regex = attributeRegex else {
            return result
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        for match in regex.matches(in: line, range: range) {
            guard match.numberOfRanges == 3,
                  let keyRange = Range(match.range(at: 1), in: line),
                  let valueRange = Range(match.range(at: 2), in: line) else {
                continue
            }

            result[String(line[keyRange])] = String(line[valueRange])
        }

        return result
    }
}
