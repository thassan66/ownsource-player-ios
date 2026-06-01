import Foundation

struct XtreamClient {
    var serverURL: URL
    var username: String
    var password: String

    func fetchChannels(sourceId: UUID) async throws -> [Channel] {
        try await fetchProviderLibrary(sourceId: sourceId).allChannels
    }

    func fetchProviderLibrary(sourceId: UUID) async throws -> ProviderImportResult {
        async let account = fetchAccountInfo()
        async let liveCategories = fetchCategories(action: "get_live_categories", kind: .live)
        async let vodCategories = fetchCategories(action: "get_vod_categories", kind: .movie)
        async let seriesCategories = fetchCategories(action: "get_series_categories", kind: .series)
        async let liveStreams = fetchLiveStreams()
        async let vodStreams = fetchVodStreams()
        async let series = fetchSeries()

        let accountInfo = try await account
        if let accountInfo, !accountInfo.isActive {
            throw AppError.providerInactive(accountInfo.status ?? "Unknown")
        }

        let resolvedLiveCategories = try await liveCategories
        let resolvedVodCategories = try await vodCategories
        let resolvedSeriesCategories = try await seriesCategories
        let categories = resolvedLiveCategories + resolvedVodCategories + resolvedSeriesCategories
        let categoryNames = categories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let liveStreamItems = try await liveStreams
        let vodStreamItems = try await vodStreams
        let seriesItems = try await series

        let liveChannels = liveStreamItems.compactMap { stream -> LiveChannel? in
            guard let streamId = stream.streamId else {
                return nil
            }

            let channel = Channel(
                sourceId: sourceId,
                name: stream.name ?? "Live Stream",
                streamURL: streamURL(path: "live", streamId: streamId, extensionValue: "ts"),
                category: categoryNames[stream.categoryId ?? ""] ?? categoryFallback(stream.categoryId, prefix: "Live"),
                mediaKind: .live,
                logoURL: stream.streamIcon,
                tvgId: stream.epgChannelId
            )

            var live = LiveChannel(channel: channel)
            live.hasCatchUp = stream.hasCatchUp
            live.catchUpDays = stream.catchUpDays
            return live
        }

        let movies = vodStreamItems.compactMap { stream -> MovieItem? in
            guard let streamId = stream.streamId else {
                return nil
            }

            let channel = Channel(
                sourceId: sourceId,
                name: stream.name ?? "Video",
                streamURL: streamURL(path: "movie", streamId: streamId, extensionValue: stream.containerExtension ?? "mp4"),
                category: categoryNames[stream.categoryId ?? ""] ?? categoryFallback(stream.categoryId, prefix: "Movies"),
                mediaKind: .movie,
                logoURL: stream.streamIcon,
                tvgId: stream.epgChannelId
            )

            var movie = MovieItem(channel: channel)
            movie.providerItemId = streamId
            movie.releaseYear = stream.releaseYear
            return movie
        }

        let seriesEpisodes = try await fetchSeriesEpisodes(
            sourceId: sourceId,
            series: seriesItems,
            categoryNames: categoryNames
        )

        return ProviderImportResult(
            account: accountInfo,
            categories: categories,
            liveChannels: liveChannels,
            movies: movies,
            seriesEpisodes: seriesEpisodes
        )
    }

    private func fetchAccountInfo() async throws -> ProviderAccountInfo? {
        let response: XtreamAccountResponse = try await fetch(action: nil)
        return response.userInfo?.accountInfo
    }

    private func fetchLiveStreams() async throws -> [XtreamStream] {
        try await fetch(action: "get_live_streams")
    }

    private func fetchVodStreams() async throws -> [XtreamStream] {
        try await fetch(action: "get_vod_streams")
    }

    private func fetchSeries() async throws -> [XtreamSeries] {
        try await fetch(action: "get_series")
    }

    private func fetchCategories(action: String, kind: ProviderCategoryKind) async throws -> [ProviderCategory] {
        let categories: [XtreamCategory] = try await fetch(action: action)
        return categories.compactMap { category in
            guard let id = category.categoryId, let name = category.categoryName else {
                return nil
            }
            return ProviderCategory(id: id, kind: kind, name: name)
        }
    }

    private func fetchSeriesEpisodes(
        sourceId: UUID,
        series: [XtreamSeries],
        categoryNames: [String: String]
    ) async throws -> [SeriesEpisode] {
        var episodes: [SeriesEpisode] = []

        for item in series {
            guard let seriesId = item.seriesId else {
                continue
            }

            let info: XtreamSeriesInfo = try await fetch(action: "get_series_info", extraQueryItems: [
                URLQueryItem(name: "series_id", value: "\(seriesId)")
            ])

            for (seasonKey, seasonEpisodes) in info.episodes {
                let seasonNumber = Int(seasonKey)
                for episode in seasonEpisodes {
                    guard let episodeId = episode.id else {
                        continue
                    }

                    let extensionValue = episode.containerExtension ?? "mp4"
                    let channel = Channel(
                        sourceId: sourceId,
                        name: episode.title ?? "\(item.name ?? "Series") Episode",
                        streamURL: streamURL(path: "series", streamId: episodeId, extensionValue: extensionValue),
                        category: categoryNames[item.categoryId ?? ""] ?? categoryFallback(item.categoryId, prefix: "Series"),
                        mediaKind: .seriesEpisode,
                        logoURL: episode.info?.movieImage ?? item.cover
                    )

                    var mapped = SeriesEpisode(channel: channel)
                    mapped.seriesTitle = item.name
                    mapped.seasonNumber = episode.season ?? seasonNumber
                    mapped.episodeNumber = episode.episodeNumber
                    mapped.providerSeriesId = seriesId
                    mapped.providerEpisodeId = episodeId
                    episodes.append(mapped)
                }
            }
        }

        return episodes
    }

    private func fetch<T: Decodable>(
        action: String?,
        extraQueryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(url: serverURL.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]

        if let action {
            queryItems.append(URLQueryItem(name: "action", value: action))
        }

        queryItems.append(contentsOf: extraQueryItems)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw AppError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func streamURL(path: String, streamId: Int, extensionValue: String) -> String {
        serverURL
            .appendingPathComponent(path)
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamId).\(extensionValue)")
            .absoluteString
    }

    private func categoryFallback(_ categoryId: String?, prefix: String) -> String {
        guard let categoryId, !categoryId.isEmpty else {
            return prefix
        }
        return "\(prefix) \(categoryId)"
    }
}

struct XtreamAccountResponse: Decodable {
    var userInfo: XtreamUserInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
    }
}

struct XtreamUserInfo: Decodable {
    var username: String?
    var status: String?
    var expDate: String?
    var activeCons: String?
    var maxConnections: String?

    enum CodingKeys: String, CodingKey {
        case username
        case status
        case expDate = "exp_date"
        case activeCons = "active_cons"
        case maxConnections = "max_connections"
    }

    var accountInfo: ProviderAccountInfo {
        ProviderAccountInfo(
            username: username,
            status: status,
            expiresAt: expDate.flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)),
            activeConnections: activeCons.flatMap(Int.init),
            maxConnections: maxConnections.flatMap(Int.init)
        )
    }
}

struct XtreamCategory: Decodable {
    var categoryId: String?
    var categoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
    }
}

struct XtreamStream: Decodable {
    var streamId: Int?
    var name: String?
    var streamIcon: String?
    var categoryId: String?
    var categoryName: String?
    var epgChannelId: String?
    var containerExtension: String?
    var tvArchive: Int?
    var tvArchiveDuration: String?
    var releaseYear: String?

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
        case categoryName = "category_name"
        case epgChannelId = "epg_channel_id"
        case containerExtension = "container_extension"
        case tvArchive = "tv_archive"
        case tvArchiveDuration = "tv_archive_duration"
        case releaseYear = "release_year"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streamId = Self.decodeFlexibleInt(container, .streamId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        epgChannelId = try container.decodeIfPresent(String.self, forKey: .epgChannelId)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
        tvArchive = Self.decodeFlexibleInt(container, .tvArchive)
        tvArchiveDuration = try container.decodeIfPresent(String.self, forKey: .tvArchiveDuration)
        releaseYear = try container.decodeIfPresent(String.self, forKey: .releaseYear)
    }

    var hasCatchUp: Bool {
        tvArchive == 1
    }

    var catchUpDays: Int? {
        tvArchiveDuration.flatMap(Int.init)
    }
}

struct XtreamSeries: Decodable {
    var seriesId: Int?
    var name: String?
    var cover: String?
    var categoryId: String?

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name
        case cover
        case categoryId = "category_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seriesId = Self.decodeFlexibleInt(container, .seriesId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        categoryId = try container.decodeIfPresent(String.self, forKey: .categoryId)
    }
}

struct XtreamSeriesInfo: Decodable {
    var episodes: [String: [XtreamEpisode]]
}

struct XtreamEpisode: Decodable {
    var id: Int?
    var episodeNumber: Int?
    var title: String?
    var containerExtension: String?
    var info: XtreamEpisodeInfo?
    var season: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNumber = "episode_num"
        case title
        case containerExtension = "container_extension"
        case info
        case season
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleInt(container, .id)
        episodeNumber = Self.decodeFlexibleInt(container, .episodeNumber)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
        info = try container.decodeIfPresent(XtreamEpisodeInfo.self, forKey: .info)
        season = Self.decodeFlexibleInt(container, .season)
    }
}

struct XtreamEpisodeInfo: Decodable {
    var movieImage: String?

    enum CodingKeys: String, CodingKey {
        case movieImage = "movie_image"
    }
}

private extension Decodable {
    static func decodeFlexibleInt<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(string)
        }

        return nil
    }
}
