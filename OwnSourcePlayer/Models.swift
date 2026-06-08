import Foundation

enum MediaSourceKind: String, Codable, CaseIterable, Identifiable {
    case m3uURL
    case m3uFile
    case xtream

    var id: String { rawValue }

    var label: String {
        switch self {
        case .m3uURL:
            return "M3U URL"
        case .m3uFile:
            return "Local M3U File"
        case .xtream:
            return "Provider Login"
        }
    }
}

struct MediaSource: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var kind: MediaSourceKind
    var location: String
    var username: String?
    var password: String?
    var createdAt: Date
    var lastRefreshAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        kind: MediaSourceKind,
        location: String,
        username: String? = nil,
        password: String? = nil,
        createdAt: Date = Date(),
        lastRefreshAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
        self.username = username
        self.password = password
        self.createdAt = createdAt
        self.lastRefreshAt = lastRefreshAt
    }
}

enum MediaKind: String, Codable, Hashable {
    case live
    case movie
    case seriesEpisode

    var isOnDemand: Bool {
        self != .live
    }
}

struct Channel: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceId: UUID
    var name: String
    var streamURL: String
    var category: String
    var mediaKind: MediaKind
    var logoURL: String?
    var tvgId: String?
    var currentProgramTitle: String?
    var nextProgramTitle: String?
    var isFavorite: Bool
    var lastWatchedAt: Date?
    var resumePosition: Double?

    init(
        id: UUID = UUID(),
        sourceId: UUID,
        name: String,
        streamURL: String,
        category: String = "Uncategorized",
        mediaKind: MediaKind? = nil,
        logoURL: String? = nil,
        tvgId: String? = nil,
        currentProgramTitle: String? = nil,
        nextProgramTitle: String? = nil,
        isFavorite: Bool = false,
        lastWatchedAt: Date? = nil,
        resumePosition: Double? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.streamURL = streamURL
        self.category = category.isEmpty ? "Uncategorized" : category
        self.mediaKind = mediaKind ?? Channel.inferredMediaKind(streamURL: streamURL, category: category)
        self.logoURL = logoURL
        self.tvgId = tvgId
        self.currentProgramTitle = currentProgramTitle
        self.nextProgramTitle = nextProgramTitle
        self.isFavorite = isFavorite
        self.lastWatchedAt = lastWatchedAt
        self.resumePosition = resumePosition
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId
        case name
        case streamURL
        case category
        case mediaKind
        case logoURL
        case tvgId
        case currentProgramTitle
        case nextProgramTitle
        case isFavorite
        case lastWatchedAt
        case resumePosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let sourceId = try container.decode(UUID.self, forKey: .sourceId)
        let name = try container.decode(String.self, forKey: .name)
        let streamURL = try container.decode(String.self, forKey: .streamURL)
        let category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Uncategorized"
        let mediaKind = try container.decodeIfPresent(MediaKind.self, forKey: .mediaKind)
        let logoURL = try container.decodeIfPresent(String.self, forKey: .logoURL)
        let tvgId = try container.decodeIfPresent(String.self, forKey: .tvgId)
        let currentProgramTitle = try container.decodeIfPresent(String.self, forKey: .currentProgramTitle)
        let nextProgramTitle = try container.decodeIfPresent(String.self, forKey: .nextProgramTitle)
        let isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        let lastWatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastWatchedAt)
        let resumePosition = try container.decodeIfPresent(Double.self, forKey: .resumePosition)

        self.init(
            id: id,
            sourceId: sourceId,
            name: name,
            streamURL: streamURL,
            category: category,
            mediaKind: mediaKind,
            logoURL: logoURL,
            tvgId: tvgId,
            currentProgramTitle: currentProgramTitle,
            nextProgramTitle: nextProgramTitle,
            isFavorite: isFavorite,
            lastWatchedAt: lastWatchedAt,
            resumePosition: resumePosition
        )
    }

    var isOnDemand: Bool {
        mediaKind.isOnDemand
    }

    private static func inferredMediaKind(streamURL: String, category: String) -> MediaKind {
        let lowerURL = streamURL.lowercased()
        let lowerCategory = category.lowercased()
        if lowerURL.contains("/series/")
            || ["series", "episode", "season"].contains(where: { lowerCategory.contains($0) }) {
            return .seriesEpisode
        }
        if lowerURL.contains("/movie/")
            || [".mp4", ".m4v", ".mov", ".mkv", ".avi"].contains(where: { lowerURL.contains($0) })
            || ["movie", "movies", "vod"].contains(where: { lowerCategory.contains($0) }) {
            return .movie
        }
        return .live
    }
}

struct EPGGuideSource: Identifiable, Codable, Hashable {
    let id: UUID
    var urlString: String
    var importedAt: Date
    var lastRefreshAt: Date?

    init(id: UUID = UUID(), urlString: String, importedAt: Date = Date(), lastRefreshAt: Date? = nil) {
        self.id = id
        self.urlString = urlString
        self.importedAt = importedAt
        self.lastRefreshAt = lastRefreshAt
    }
}

struct PlaylistImportResult {
    var source: MediaSource
    var channels: [Channel]
}

struct EPGProgram: Identifiable, Codable, Hashable {
    let id: UUID
    var channelId: String
    var title: String
    var startAt: Date
    var endAt: Date

    init(id: UUID = UUID(), channelId: String, title: String, startAt: Date, endAt: Date) {
        self.id = id
        self.channelId = channelId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
    }
}

enum AppError: LocalizedError {
    case invalidURL
    case emptyPlaylist
    case importFailed(String)
    case unsupportedFile
    case missingCredentials
    case providerInactive(String)
    case networkUnavailable(String)
    case invalidServerResponse
    case httpStatus(Int, String)
    case decodingFailed(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTP or HTTPS URL."
        case .emptyPlaylist:
            return "No playable streams were found in this playlist."
        case .importFailed(let message):
            return message
        case .unsupportedFile:
            return "Choose a valid M3U or M3U8 playlist file."
        case .missingCredentials:
            return "Enter a server URL, username, and password."
        case .providerInactive(let status):
            return "The provider account is not active. Status: \(status)."
        case .networkUnavailable(let message):
            return "The server could not be reached. \(message)"
        case .invalidServerResponse:
            return "The server returned an invalid response."
        case .httpStatus(let statusCode, let context):
            return "\(context) failed with HTTP status \(statusCode)."
        case .decodingFailed(let context):
            return "\(context) returned data in an unexpected format."
        case .storageFailed(let message):
            return "The library could not be saved or loaded. \(message)"
        }
    }
}
