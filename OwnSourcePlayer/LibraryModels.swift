import Foundation

struct LiveChannel: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceId: UUID
    var name: String
    var streamURL: String
    var category: String
    var logoURL: String?
    var tvgId: String?
    var hasCatchUp: Bool
    var catchUpDays: Int?
    var isFavorite: Bool
    var lastWatchedAt: Date?
    var resumePosition: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceId
        case name
        case streamURL
        case category
        case logoURL
        case tvgId
        case hasCatchUp
        case catchUpDays
        case isFavorite
        case lastWatchedAt
        case resumePosition
    }

    init(channel: Channel) {
        id = channel.id
        sourceId = channel.sourceId
        name = channel.name
        streamURL = channel.streamURL
        category = channel.category
        logoURL = channel.logoURL
        tvgId = channel.tvgId
        hasCatchUp = false
        catchUpDays = nil
        isFavorite = channel.isFavorite
        lastWatchedAt = channel.lastWatchedAt
        resumePosition = channel.resumePosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceId = try container.decode(UUID.self, forKey: .sourceId)
        name = try container.decode(String.self, forKey: .name)
        streamURL = try container.decode(String.self, forKey: .streamURL)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Uncategorized"
        logoURL = try container.decodeIfPresent(String.self, forKey: .logoURL)
        tvgId = try container.decodeIfPresent(String.self, forKey: .tvgId)
        hasCatchUp = try container.decodeIfPresent(Bool.self, forKey: .hasCatchUp) ?? false
        catchUpDays = try container.decodeIfPresent(Int.self, forKey: .catchUpDays)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastWatchedAt = try container.decodeIfPresent(Date.self, forKey: .lastWatchedAt)
        resumePosition = try container.decodeIfPresent(Double.self, forKey: .resumePosition)
    }

    var channel: Channel {
        Channel(
            id: id,
            sourceId: sourceId,
            name: name,
            streamURL: streamURL,
            category: category,
            mediaKind: .live,
            logoURL: logoURL,
            tvgId: tvgId,
            isFavorite: isFavorite,
            lastWatchedAt: lastWatchedAt,
            resumePosition: resumePosition
        )
    }
}

struct MovieItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceId: UUID
    var title: String
    var streamURL: String
    var category: String
    var posterURL: String?
    var providerItemId: Int?
    var releaseYear: String?
    var isFavorite: Bool
    var lastWatchedAt: Date?
    var resumePosition: Double?

    init(channel: Channel) {
        id = channel.id
        sourceId = channel.sourceId
        title = channel.name
        streamURL = channel.streamURL
        category = channel.category
        posterURL = channel.logoURL
        providerItemId = nil
        releaseYear = nil
        isFavorite = channel.isFavorite
        lastWatchedAt = channel.lastWatchedAt
        resumePosition = channel.resumePosition
    }

    var channel: Channel {
        Channel(
            id: id,
            sourceId: sourceId,
            name: title,
            streamURL: streamURL,
            category: category,
            mediaKind: .movie,
            logoURL: posterURL,
            isFavorite: isFavorite,
            lastWatchedAt: lastWatchedAt,
            resumePosition: resumePosition
        )
    }
}

struct SeriesEpisode: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceId: UUID
    var title: String
    var streamURL: String
    var category: String
    var posterURL: String?
    var seriesTitle: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var providerSeriesId: Int?
    var providerEpisodeId: Int?
    var isFavorite: Bool
    var lastWatchedAt: Date?
    var resumePosition: Double?

    init(channel: Channel) {
        id = channel.id
        sourceId = channel.sourceId
        title = channel.name
        streamURL = channel.streamURL
        category = channel.category
        posterURL = channel.logoURL
        seriesTitle = nil
        seasonNumber = nil
        episodeNumber = nil
        providerSeriesId = nil
        providerEpisodeId = nil
        isFavorite = channel.isFavorite
        lastWatchedAt = channel.lastWatchedAt
        resumePosition = channel.resumePosition
    }

    var channel: Channel {
        Channel(
            id: id,
            sourceId: sourceId,
            name: title,
            streamURL: streamURL,
            category: category,
            mediaKind: .seriesEpisode,
            logoURL: posterURL,
            isFavorite: isFavorite,
            lastWatchedAt: lastWatchedAt,
            resumePosition: resumePosition
        )
    }
}

struct MediaLibrary: Codable, Hashable {
    var liveChannels: [LiveChannel]
    var movies: [MovieItem]
    var seriesEpisodes: [SeriesEpisode]

    init(
        liveChannels: [LiveChannel] = [],
        movies: [MovieItem] = [],
        seriesEpisodes: [SeriesEpisode] = []
    ) {
        self.liveChannels = liveChannels
        self.movies = movies
        self.seriesEpisodes = seriesEpisodes
    }

    var allChannels: [Channel] {
        liveChannels.map(\.channel)
            + movies.map(\.channel)
            + seriesEpisodes.map(\.channel)
    }

    var count: Int {
        liveChannels.count + movies.count + seriesEpisodes.count
    }

    static func from(channels: [Channel]) -> MediaLibrary {
        MediaLibrary(
            liveChannels: channels.filter { $0.mediaKind == .live }.map(LiveChannel.init),
            movies: channels.filter { $0.mediaKind == .movie }.map(MovieItem.init),
            seriesEpisodes: channels.filter { $0.mediaKind == .seriesEpisode }.map(SeriesEpisode.init)
        )
    }

    func removingSource(_ sourceId: UUID) -> MediaLibrary {
        MediaLibrary(
            liveChannels: liveChannels.filter { $0.sourceId != sourceId },
            movies: movies.filter { $0.sourceId != sourceId },
            seriesEpisodes: seriesEpisodes.filter { $0.sourceId != sourceId }
        )
    }

    func replacingSource(_ sourceId: UUID, with channels: [Channel]) -> MediaLibrary {
        let retained = removingSource(sourceId).allChannels
        return MediaLibrary.from(channels: retained + channels)
    }

    func replacingSource(_ sourceId: UUID, with importResult: ProviderImportResult) -> MediaLibrary {
        let retained = removingSource(sourceId)
        return MediaLibrary(
            liveChannels: retained.liveChannels + importResult.liveChannels,
            movies: retained.movies + importResult.movies,
            seriesEpisodes: retained.seriesEpisodes + importResult.seriesEpisodes
        )
    }

    func updatingFavorite(channelId: UUID) -> MediaLibrary {
        var updated = self
        if let index = updated.liveChannels.firstIndex(where: { $0.id == channelId }) {
            updated.liveChannels[index].isFavorite.toggle()
        } else if let index = updated.movies.firstIndex(where: { $0.id == channelId }) {
            updated.movies[index].isFavorite.toggle()
        } else if let index = updated.seriesEpisodes.firstIndex(where: { $0.id == channelId }) {
            updated.seriesEpisodes[index].isFavorite.toggle()
        }
        return updated
    }

    func markingWatched(channelId: UUID, at date: Date = Date()) -> MediaLibrary {
        var updated = self
        if let index = updated.liveChannels.firstIndex(where: { $0.id == channelId }) {
            updated.liveChannels[index].lastWatchedAt = date
        } else if let index = updated.movies.firstIndex(where: { $0.id == channelId }) {
            updated.movies[index].lastWatchedAt = date
        } else if let index = updated.seriesEpisodes.firstIndex(where: { $0.id == channelId }) {
            updated.seriesEpisodes[index].lastWatchedAt = date
        }
        return updated
    }

    func updatingResumePosition(channelId: UUID, seconds: Double, at date: Date = Date()) -> MediaLibrary {
        var updated = self
        if let index = updated.movies.firstIndex(where: { $0.id == channelId }) {
            updated.movies[index].resumePosition = max(seconds, 0)
            updated.movies[index].lastWatchedAt = date
        } else if let index = updated.seriesEpisodes.firstIndex(where: { $0.id == channelId }) {
            updated.seriesEpisodes[index].resumePosition = max(seconds, 0)
            updated.seriesEpisodes[index].lastWatchedAt = date
        }
        return updated
    }
}

struct ProviderImportResult: Codable, Hashable {
    var account: ProviderAccountInfo?
    var categories: [ProviderCategory]
    var liveChannels: [LiveChannel]
    var movies: [MovieItem]
    var seriesEpisodes: [SeriesEpisode]

    var allChannels: [Channel] {
        liveChannels.map(\.channel)
            + movies.map(\.channel)
            + seriesEpisodes.map(\.channel)
    }
}

struct ProviderAccountInfo: Codable, Hashable {
    var username: String?
    var status: String?
    var expiresAt: Date?
    var activeConnections: Int?
    var maxConnections: Int?

    var isActive: Bool {
        (status ?? "Active").localizedCaseInsensitiveCompare("Active") == .orderedSame
    }
}

enum ProviderCategoryKind: String, Codable, Hashable {
    case live
    case movie
    case series
}

struct ProviderCategory: Identifiable, Codable, Hashable {
    var id: String
    var kind: ProviderCategoryKind
    var name: String
}
