import Foundation

enum MediaURLValidator {
    static func httpURL(from value: String, defaultScheme: String = "https") -> URL? {
        var trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            trimmed = "\(defaultScheme):\(trimmed)"
        } else if !trimmed.contains("://") {
            trimmed = "\(defaultScheme)://\(trimmed)"
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? trimmed
        guard let url = URL(string: trimmed) ?? URL(string: encoded),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else {
            return nil
        }

        return url
    }
}
