import Foundation

enum MediaURLValidator {
    static func httpURL(from value: String) -> URL? {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }

        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else {
            return nil
        }

        return url
    }
}
