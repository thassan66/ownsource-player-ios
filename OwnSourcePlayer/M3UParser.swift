import Foundation

struct ParsedChannel {
    var name: String
    var streamURL: String
    var category: String
    var logoURL: String?
    var tvgId: String?
}

enum M3UParser {
    static func parse(_ text: String) -> [ParsedChannel] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var channels: [ParsedChannel] = []
        var pendingInfo: [String: String] = [:]
        var pendingName: String?

        for line in lines {
            if line.hasPrefix("#EXTINF") {
                pendingInfo = attributes(from: line)
                pendingName = displayName(from: line)
                continue
            }

            if line.hasPrefix("#") {
                continue
            }

            guard line.lowercased().hasPrefix("http") else {
                continue
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
        let pattern = #"([\w-]+)="([^"]*)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
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

