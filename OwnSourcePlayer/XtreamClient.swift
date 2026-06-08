import Foundation

struct XtreamClient {
    private static let initialSeriesDetailLimit = 30

    var serverURL: URL
    var username: String
    var password: String

    func fetchChannels(sourceId: UUID) async throws -> [Channel] {
        try await fetchProviderLibrary(sourceId: sourceId).allChannels
    }

    func fetchProviderLibrary(sourceId: UUID) async throws -> ProviderImportResult {
        // Import live channels first. Large providers can expose thousands of VOD/series items, and expanding
        // series details requires one request per series, which makes initial setup look stuck.
        async let account = fetchOptionalAccountInfo()
        async let liveCategories = fetchOptionalCategories(action: "get_live_categories", kind: .live)
        async let liveStreams = fetchLiveStreams()

        let accountInfo = await account
        if let accountInfo, !accountInfo.isActive {
            throw AppError.providerInactive(accountInfo.status ?? "Unknown")
        }

        let resolvedLiveCategories = await liveCategories
        let liveCategoryNames = resolvedLiveCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let liveStreamItems: [XtreamStream]
        do {
            liveStreamItems = try await liveStreams
        } catch AppError.httpStatus(403, _) {
            return try await fetchM3UProviderLibrary(
                sourceId: sourceId,
                accountInfo: accountInfo,
                categories: resolvedLiveCategories
            )
        }

        let liveChannels = liveStreamItems.compactMap { stream -> LiveChannel? in
            guard let streamId = stream.streamId else {
                return nil
            }

            let channel = Channel(
                sourceId: sourceId,
                name: stream.name ?? "Live Stream",
                streamURL: streamURL(path: "live", streamId: streamId, extensionValue: "m3u8"),
                category: liveCategoryNames[stream.categoryId ?? ""] ?? categoryFallback(stream.categoryId, prefix: "Live"),
                mediaKind: .live,
                logoURL: stream.streamIcon,
                tvgId: stream.epgChannelId
            )

            var live = LiveChannel(channel: channel)
            live.hasCatchUp = stream.hasCatchUp
            live.catchUpDays = stream.catchUpDays
            return live
        }

        if liveChannels.isEmpty {
            return try await fetchM3UProviderLibrary(
                sourceId: sourceId,
                accountInfo: accountInfo,
                categories: resolvedLiveCategories
            )
        }

        async let vodCategories = fetchOptionalCategories(action: "get_vod_categories", kind: .movie)
        async let vodStreams = fetchOptionalVodStreams()
        async let seriesCategories = fetchOptionalCategories(action: "get_series_categories", kind: .series)
        async let series = fetchOptionalSeries()

        let resolvedVodCategories = await vodCategories
        let resolvedSeriesCategories = await seriesCategories
        let allCategories = resolvedLiveCategories + resolvedVodCategories + resolvedSeriesCategories
        let categoryNames = allCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let vodStreamItems = await vodStreams
        let seriesItems = await series

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
            series: Array(seriesItems.prefix(Self.initialSeriesDetailLimit)),
            categoryNames: categoryNames
        )

        return ProviderImportResult(
            account: accountInfo,
            categories: allCategories,
            liveChannels: liveChannels,
            movies: movies,
            seriesEpisodes: seriesEpisodes
        )
    }

    private func fetchProviderMoviesOnly(
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        liveCategories: [ProviderCategory]
    ) async throws -> ProviderImportResult {
        async let vodCategories = fetchOptionalCategories(action: "get_vod_categories", kind: .movie)
        async let vodStreams = fetchOptionalVodStreams()
        let resolvedVodCategories = await vodCategories
        let vodCategoryNames = resolvedVodCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let vodStreamItems = await vodStreams

        let movies = vodStreamItems.compactMap { stream -> MovieItem? in
            guard let streamId = stream.streamId else {
                return nil
            }

            let channel = Channel(
                sourceId: sourceId,
                name: stream.name ?? "Video",
                streamURL: streamURL(path: "movie", streamId: streamId, extensionValue: stream.containerExtension ?? "mp4"),
                category: vodCategoryNames[stream.categoryId ?? ""] ?? categoryFallback(stream.categoryId, prefix: "Movies"),
                mediaKind: .movie,
                logoURL: stream.streamIcon,
                tvgId: stream.epgChannelId
            )

            var movie = MovieItem(channel: channel)
            movie.providerItemId = streamId
            movie.releaseYear = stream.releaseYear
            return movie
        }

        guard movies.isEmpty == false else {
            return ProviderImportResult(
                account: accountInfo,
                categories: liveCategories + resolvedVodCategories,
                liveChannels: [],
                movies: [],
                seriesEpisodes: []
            )
        }

        return ProviderImportResult(
            account: accountInfo,
            categories: liveCategories + resolvedVodCategories,
            liveChannels: [],
            movies: movies,
            seriesEpisodes: []
        )
    }

    private func fetchAccountInfo() async throws -> ProviderAccountInfo? {
        let response: XtreamAccountResponse = try await fetch(action: nil)
        return response.userInfo?.accountInfo
    }

    private func fetchOptionalAccountInfo() async -> ProviderAccountInfo? {
        try? await fetchAccountInfo()
    }

    private func fetchLiveStreams() async throws -> [XtreamStream] {
        try await fetchArray(action: "get_live_streams")
    }

    private func fetchVodStreams() async throws -> [XtreamStream] {
        try await fetchArray(action: "get_vod_streams")
    }

    private func fetchSeries() async throws -> [XtreamSeries] {
        try await fetchArray(action: "get_series")
    }

    private func fetchCategories(action: String, kind: ProviderCategoryKind) async throws -> [ProviderCategory] {
        let categories: [XtreamCategory] = try await fetchArray(action: action)
        return categories.compactMap { category in
            guard let id = category.categoryId, let name = category.categoryName else {
                return nil
            }
            return ProviderCategory(id: id, kind: kind, name: name)
        }
    }

    private func fetchOptionalCategories(action: String, kind: ProviderCategoryKind) async -> [ProviderCategory] {
        (try? await fetchCategories(action: action, kind: kind)) ?? []
    }

    private func fetchOptionalVodStreams() async -> [XtreamStream] {
        (try? await fetchVodStreams()) ?? []
    }

    private func fetchOptionalSeries() async -> [XtreamSeries] {
        (try? await fetchSeries()) ?? []
    }

    private func fetchM3UProviderLibrary(
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        categories: [ProviderCategory]
    ) async throws -> ProviderImportResult {
        guard let request = playlistRequest() else {
            throw AppError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, context: "Provider M3U playlist")
            let playlist = try providerText(from: data, context: "Provider M3U playlist")
            let parsed = M3UParser.parse(playlist)
            let channels = parsed.map { item in
                Channel(
                    sourceId: sourceId,
                    name: item.name,
                    streamURL: item.streamURL,
                    category: item.category,
                    logoURL: item.logoURL,
                    tvgId: item.tvgId
                )
            }
            let library = MediaLibrary.from(channels: channels)

            return ProviderImportResult(
                account: accountInfo,
                categories: categories,
                liveChannels: library.liveChannels,
                movies: library.movies,
                seriesEpisodes: library.seriesEpisodes
            )
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.networkUnavailable(error.localizedDescription)
        } catch {
            throw AppError.importFailed(error.localizedDescription)
        }
    }

    private func fetchSeriesEpisodes(
        sourceId: UUID,
        series: [XtreamSeries],
        categoryNames: [String: String]
    ) async throws -> [SeriesEpisode] {
        var episodes: [SeriesEpisode] = []

        for item in series {
            // Some panels return incomplete series shells; skip those instead of failing the full import.
            guard let seriesId = item.seriesId else {
                continue
            }

            let info: XtreamSeriesInfo
            do {
                info = try await fetch(action: "get_series_info", extraQueryItems: [
                    URLQueryItem(name: "series_id", value: "\(seriesId)")
                ])
            } catch {
                continue
            }

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
        guard let request = providerRequest(action: action, extraQueryItems: extraQueryItems) else {
            throw AppError.invalidURL
        }

        // All provider calls flow through this path so HTTP, network, and JSON errors stay user-readable.
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, context: providerContext(for: action))
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.networkUnavailable(error.localizedDescription)
        } catch is DecodingError {
            throw AppError.decodingFailed(providerContext(for: action))
        } catch {
            throw AppError.importFailed(error.localizedDescription)
        }
    }

    private func fetchArray<T: Decodable>(
        action: String?,
        extraQueryItems: [URLQueryItem] = []
    ) async throws -> [T] {
        guard let request = providerRequest(action: action, extraQueryItems: extraQueryItems) else {
            throw AppError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, context: providerContext(for: action))
            return try Self.decodeProviderArray(T.self, from: data)
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.networkUnavailable(error.localizedDescription)
        } catch is DecodingError {
            throw AppError.decodingFailed(providerContext(for: action))
        } catch {
            throw AppError.importFailed(error.localizedDescription)
        }
    }

    private func providerRequest(action: String?, extraQueryItems: [URLQueryItem]) -> URLRequest? {
        let apiURL = serverURL.lastPathComponent.localizedCaseInsensitiveCompare("player_api.php") == .orderedSame
            ? serverURL
            : serverURL.appendingPathComponent("player_api.php")
        var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)
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
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("OwnSource Player/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        return request
    }

    private func playlistRequest() -> URLRequest? {
        let baseURL = serverURL.lastPathComponent.localizedCaseInsensitiveCompare("player_api.php") == .orderedSame
            ? serverURL.deletingLastPathComponent()
            : serverURL
        let playlistURL = baseURL.appendingPathComponent("get.php")
        var components = URLComponents(url: playlistURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "m3u8")
        ]

        guard let url = components?.url else {
            return nil
        }

        return Self.mediaRequest(url: url)
    }

    static func mediaRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        for (field, value) in mediaHTTPHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static var mediaHTTPHeaders: [String: String] {
        [
            "User-Agent": "VLC/3.0.21 LibVLC/3.0.21",
            "Accept": "*/*",
            "Connection": "keep-alive"
        ]
    }

    private func providerText(from data: Data, context: String) throws -> String {
        guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AppError.importFailed("\(context) could not be read as text.")
        }
        return value
    }

    static func decodeProviderArray<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()

        if let direct = try? decoder.decode([T].self, from: data) {
            return direct
        }

        if let keyed = try? decoder.decode([String: T].self, from: data) {
            return keyed
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .map(\.value)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Provider response is not an array or object.")
            )
        }

        for key in providerArrayKeys {
            guard let value = dictionary[key] else {
                continue
            }

            if let items = decodeProviderArrayValue(T.self, value: value, decoder: decoder) {
                return items
            }
        }

        if let items = decodeProviderDictionaryValues(T.self, dictionary: dictionary, decoder: decoder),
           !items.isEmpty || dictionary.isEmpty {
            return items
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Provider response did not contain decodable items.")
        )
    }

    private static let providerArrayKeys = [
        "data",
        "items",
        "results",
        "streams",
        "live_streams",
        "vod_streams",
        "movies",
        "series",
        "categories",
        "available_channels"
    ]

    private static func decodeProviderArrayValue<T: Decodable>(
        _ type: T.Type,
        value: Any,
        decoder: JSONDecoder
    ) -> [T]? {
        if let array = value as? [Any] {
            return decodeProviderArrayItems(T.self, values: array, decoder: decoder)
        }

        if let dictionary = value as? [String: Any] {
            return decodeProviderDictionaryValues(T.self, dictionary: dictionary, decoder: decoder)
        }

        return nil
    }

    private static func decodeProviderDictionaryValues<T: Decodable>(
        _ type: T.Type,
        dictionary: [String: Any],
        decoder: JSONDecoder
    ) -> [T]? {
        let values = dictionary
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)
        return decodeProviderArrayItems(T.self, values: values, decoder: decoder)
    }

    private static func decodeProviderArrayItems<T: Decodable>(
        _ type: T.Type,
        values: [Any],
        decoder: JSONDecoder
    ) -> [T]? {
        if values.isEmpty {
            return []
        }

        let items = values.compactMap { value -> T? in
            guard JSONSerialization.isValidJSONObject(value),
                  let itemData = try? JSONSerialization.data(withJSONObject: value) else {
                return nil
            }
            return try? decoder.decode(T.self, from: itemData)
        }

        return items.isEmpty ? nil : items
    }

    private func validateHTTPResponse(_ response: URLResponse, context: String) throws {
        guard let response = response as? HTTPURLResponse else {
            throw AppError.invalidServerResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AppError.httpStatus(response.statusCode, context)
        }
    }

    private func providerContext(for action: String?) -> String {
        switch action {
        case nil:
            return "Provider account"
        case "get_live_categories":
            return "Provider live categories"
        case "get_vod_categories":
            return "Provider movie categories"
        case "get_series_categories":
            return "Provider series categories"
        case "get_live_streams":
            return "Provider live streams"
        case "get_vod_streams":
            return "Provider movies"
        case "get_series":
            return "Provider series list"
        case "get_series_info":
            return "Provider series details"
        default:
            return "Provider request"
        }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = Self.decodeFlexibleString(container, .username)
        status = Self.decodeFlexibleString(container, .status)
        expDate = Self.decodeFlexibleString(container, .expDate)
        activeCons = Self.decodeFlexibleString(container, .activeCons)
        maxConnections = Self.decodeFlexibleString(container, .maxConnections)
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = Self.decodeFlexibleString(container, .categoryId)
        categoryName = Self.decodeFlexibleString(container, .categoryName)
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
        name = Self.decodeFlexibleString(container, .name)
        streamIcon = Self.decodeFlexibleString(container, .streamIcon)
        categoryId = Self.decodeFlexibleString(container, .categoryId)
        categoryName = Self.decodeFlexibleString(container, .categoryName)
        epgChannelId = Self.decodeFlexibleString(container, .epgChannelId)
        containerExtension = Self.decodeFlexibleString(container, .containerExtension)
        tvArchive = Self.decodeFlexibleInt(container, .tvArchive)
        tvArchiveDuration = Self.decodeFlexibleString(container, .tvArchiveDuration)
        releaseYear = Self.decodeFlexibleString(container, .releaseYear)
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
        name = Self.decodeFlexibleString(container, .name)
        cover = Self.decodeFlexibleString(container, .cover)
        categoryId = Self.decodeFlexibleString(container, .categoryId)
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
        title = Self.decodeFlexibleString(container, .title)
        containerExtension = Self.decodeFlexibleString(container, .containerExtension)
        info = try? container.decodeIfPresent(XtreamEpisodeInfo.self, forKey: .info)
        season = Self.decodeFlexibleInt(container, .season)
    }
}

struct XtreamEpisodeInfo: Decodable {
    var movieImage: String?

    enum CodingKeys: String, CodingKey {
        case movieImage = "movie_image"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        movieImage = Self.decodeFlexibleString(container, .movieImage)
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

    static func decodeFlexibleString<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return "\(value)"
        }

        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return "\(value)"
        }

        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value ? "1" : "0"
        }

        return nil
    }
}
