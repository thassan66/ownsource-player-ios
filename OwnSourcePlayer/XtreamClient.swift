import Foundation

enum XtreamImportMode {
    case fast
    case full

    var seriesDetailLimit: Int {
        switch self {
        case .fast:
            return 0
        case .full:
            return 30
        }
    }

    var shouldReconcileWithM3U: Bool {
        false
    }

    var optionalRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 12
        case .full:
            return 35
        }
    }

    var accountRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 10
        case .full:
            return 30
        }
    }

    var categoryRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 8
        case .full:
            return 25
        }
    }

    var liveStreamRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 45
        case .full:
            return 60
        }
    }

    var vodStreamRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 12
        case .full:
            return 60
        }
    }

    var seriesRequestTimeout: TimeInterval {
        switch self {
        case .fast:
            return 12
        case .full:
            return 60
        }
    }

    var optionalRequestAttempts: Int {
        switch self {
        case .fast:
            return 1
        case .full:
            return 2
        }
    }

    var fallbackPlaylistTimeout: TimeInterval {
        switch self {
        case .fast:
            return 240
        case .full:
            return 300
        }
    }

    var prefersPlaylistImport: Bool {
        switch self {
        case .fast:
            return true
        case .full:
            return false
        }
    }
}

private struct OptionalProviderResult<Item> {
    var items: [Item]
    var didTimeOut: Bool
}

private struct ProviderImportAttempt {
    var result: ProviderImportResult?
    var error: Error?
}

struct ProviderHealthReport: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceId: UUID
    var checkedAt: Date
    var endpoints: [ProviderEndpointHealth]

    init(id: UUID = UUID(), sourceId: UUID, checkedAt: Date = Date(), endpoints: [ProviderEndpointHealth]) {
        self.id = id
        self.sourceId = sourceId
        self.checkedAt = checkedAt
        self.endpoints = endpoints
    }

    var isHealthy: Bool {
        endpoints.contains { $0.status == .ok }
    }
}

struct ProviderEndpointHealth: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var status: ProviderEndpointStatus
    var responseTime: TimeInterval?
    var itemCount: Int?
    var message: String?
}

enum ProviderEndpointStatus: String, Codable, Hashable {
    case ok
    case empty
    case timedOut
    case failed

    var title: String {
        switch self {
        case .ok:
            return "OK"
        case .empty:
            return "Empty"
        case .timedOut:
            return "Timed out"
        case .failed:
            return "Failed"
        }
    }
}

struct XtreamClient {
    private static let seriesDetailConcurrencyLimit = 6

    var serverURL: URL
    var username: String
    var password: String

    func fetchChannels(sourceId: UUID) async throws -> [Channel] {
        try await fetchProviderLibrary(sourceId: sourceId, mode: .fast).allChannels
    }

    func checkHealth(sourceId: UUID) async -> ProviderHealthReport {
        let account = await endpointHealth(name: "Account", action: nil) { () async throws -> Int in
            let account = try await fetchAccountInfo(timeout: 8, maxAttempts: 1)
            return account == nil ? 0 : 1
        }
        let movies = await endpointHealth(name: "Movies", action: "get_vod_streams") {
            try await fetchVodStreams(timeout: 8, maxAttempts: 1).count
        }
        let series = await endpointHealth(name: "Series", action: "get_series") {
            try await fetchSeries(timeout: 8, maxAttempts: 1).count
        }
        let live = await endpointHealth(name: "Live", action: "get_live_streams") {
            try await fetchLiveStreams(timeout: 8, maxAttempts: 1).count
        }
        let m3u = await playlistHealth()

        return ProviderHealthReport(
            sourceId: sourceId,
            endpoints: [account, live, movies, series, m3u]
        )
    }

    func fetchEpisodes(for series: SeriesItem) async throws -> [SeriesEpisode] {
        guard let providerSeriesId = series.providerSeriesId else {
            return []
        }

        let item = XtreamSeries(
            seriesId: providerSeriesId,
            name: series.title,
            cover: series.posterURL,
            categoryId: nil
        )
        return await fetchSeriesEpisodes(
            sourceId: series.sourceId,
            item: item,
            categoryNames: [:],
            fallbackCategory: series.category
        )
    }

    func fetchProviderLibrary(sourceId: UUID, mode: XtreamImportMode = .fast) async throws -> ProviderImportResult {
        switch mode {
        case .fast:
            return try await fetchFastProviderLibrary(sourceId: sourceId)
        case .full:
            return try await fetchProviderAPILibrary(sourceId: sourceId, mode: mode)
        }
    }

    private func fetchFastProviderLibrary(sourceId: UUID) async throws -> ProviderImportResult {
        if XtreamImportMode.fast.prefersPlaylistImport {
            do {
                let result = try await fetchM3UProviderLibrary(
                    sourceId: sourceId,
                    accountInfo: nil,
                    categories: [],
                    timeout: XtreamImportMode.fast.fallbackPlaylistTimeout
                )
                if result.hasContent {
                    return result
                }
            } catch {
                print("Xtream M3U import failed: \(error.localizedDescription)")
            }
        }

        // Run sequentially to respect server rate-limiting and connection concurrency limits.
        // Try standard Xtream API if the playlist export is unavailable.
        do {
            let result = try await fetchProviderAPILibrary(sourceId: sourceId, mode: .fast)
            if result.hasContent {
                return result
            }
        } catch {
            print("Xtream API import failed: \(error.localizedDescription)")
        }

        // Try M3U playlist download fallback.
        return try await fetchM3UProviderLibrary(
            sourceId: sourceId,
            accountInfo: nil,
            categories: [],
            timeout: XtreamImportMode.fast.fallbackPlaylistTimeout
        )
    }

    private func fetchProviderAPILibrary(sourceId: UUID, mode: XtreamImportMode) async throws -> ProviderImportResult {
        // Treat provider sections independently. Many panels have one slow endpoint; do not block movies
        // or series just because live channels or the full M3U export timed out.
        // Do not let the optional account endpoint gate catalog loading. Some panels respond slowly
        // to player_api.php without an action even when content and M3U endpoints are healthy.
        let accountTask: Task<ProviderAccountInfo?, Never>?
        switch mode {
        case .fast:
            accountTask = nil
        case .full:
            accountTask = Task {
                await fetchOptionalAccountInfo(mode: mode)
            }
        }

        // Run stream fetches sequentially to prevent server rate-limiting / connection limit blocks
        let liveStreamResult = await fetchOptionalLiveStreams(mode: mode)
        let vodStreamResult = await fetchOptionalVodStreams(mode: mode)
        let seriesResult = await fetchOptionalSeries(mode: mode)

        let resolvedVodCategories = vodStreamResult.items.isEmpty
            ? []
            : await fetchOptionalCategories(action: "get_vod_categories", kind: .movie, mode: mode)
        let resolvedSeriesCategories = seriesResult.items.isEmpty
            ? []
            : await fetchOptionalCategories(action: "get_series_categories", kind: .series, mode: mode)
        let resolvedLiveCategories = liveStreamResult.items.isEmpty
            ? []
            : await fetchOptionalCategories(action: "get_live_categories", kind: .live, mode: mode)
        let allCategories = resolvedLiveCategories + resolvedVodCategories + resolvedSeriesCategories
        let liveCategoryNames = resolvedLiveCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let categoryNames = allCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let liveStreamItems = liveStreamResult.items
        let vodStreamItems = vodStreamResult.items
        let xtreamSeriesItems = seriesResult.items

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

        let providerSeriesItems = xtreamSeriesItems.compactMap { item -> SeriesItem? in
            guard let seriesId = item.seriesId else {
                return nil
            }

            return SeriesItem(
                sourceId: sourceId,
                title: item.name ?? "Series",
                category: categoryNames[item.categoryId ?? ""] ?? categoryFallback(item.categoryId, prefix: "Series"),
                posterURL: item.cover,
                providerSeriesId: seriesId
            )
        }

        let seriesEpisodes = try await fetchSeriesEpisodes(
            sourceId: sourceId,
            series: Array(xtreamSeriesItems.prefix(mode.seriesDetailLimit)),
            categoryNames: categoryNames
        )

        let accountInfo = await accountTask?.value
        if let accountInfo, !accountInfo.isActive {
            throw AppError.providerInactive(accountInfo.status ?? "Unknown")
        }

        let m3uImport: ProviderImportResult?
        if mode.shouldReconcileWithM3U {
            m3uImport = await fetchOptionalM3UProviderLibrary(
                sourceId: sourceId,
                accountInfo: accountInfo,
                categories: allCategories,
                timeout: mode.fallbackPlaylistTimeout
            )
        } else {
            m3uImport = nil
        }

        let resolvedMovies = m3uImport?.movies.isEmpty == false ? m3uImport?.movies ?? movies : movies
        let resolvedSeriesItems = providerSeriesItems
        let resolvedSeriesEpisodes = m3uImport?.seriesEpisodes.isEmpty == false
            ? m3uImport?.seriesEpisodes ?? seriesEpisodes
            : seriesEpisodes

        if liveChannels.isEmpty, resolvedMovies.isEmpty, resolvedSeriesItems.isEmpty, resolvedSeriesEpisodes.isEmpty {
            do {
                return try await fetchM3UProviderLibrary(
                    sourceId: sourceId,
                    accountInfo: accountInfo,
                    categories: allCategories,
                    timeout: mode.fallbackPlaylistTimeout
                )
            } catch {
                throw error
            }
        }

        return ProviderImportResult(
            account: accountInfo,
            categories: allCategories,
            liveChannels: liveChannels,
            movies: resolvedMovies,
            seriesItems: resolvedSeriesItems,
            seriesEpisodes: resolvedSeriesEpisodes
        )
    }

    private func fetchProviderMoviesOnly(
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        liveCategories: [ProviderCategory]
    ) async throws -> ProviderImportResult {
        async let vodCategories = fetchOptionalCategories(action: "get_vod_categories", kind: .movie, mode: .fast)
        async let vodStreams = fetchOptionalVodStreams(mode: .fast)
        let resolvedVodCategories = await vodCategories
        let vodCategoryNames = resolvedVodCategories.reduce(into: [String: String]()) { result, category in
            result[category.id] = category.name
        }
        let vodStreamItems = await vodStreams.items

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
                seriesItems: [],
                seriesEpisodes: []
            )
        }

        return ProviderImportResult(
            account: accountInfo,
            categories: liveCategories + resolvedVodCategories,
            liveChannels: [],
            movies: movies,
            seriesItems: [],
            seriesEpisodes: []
        )
    }

    func fetchAccountInfo(timeout: TimeInterval = 30, maxAttempts: Int = 2) async throws -> ProviderAccountInfo? {
        let response: XtreamAccountResponse = try await fetch(action: nil, timeout: timeout, maxAttempts: maxAttempts)
        return response.userInfo?.accountInfo
    }

    private func fetchOptionalAccountInfo(mode: XtreamImportMode) async -> ProviderAccountInfo? {
        try? await fetchAccountInfo(timeout: mode.accountRequestTimeout, maxAttempts: mode.optionalRequestAttempts)
    }

    private func fetchLiveStreams(timeout: TimeInterval = 30, maxAttempts: Int = 2) async throws -> [XtreamStream] {
        try await fetchArray(action: "get_live_streams", timeout: timeout, maxAttempts: maxAttempts)
    }

    private func fetchOptionalLiveStreams(mode: XtreamImportMode) async -> OptionalProviderResult<XtreamStream> {
        await optionalProviderResult {
            try await fetchLiveStreams(timeout: mode.liveStreamRequestTimeout, maxAttempts: mode.optionalRequestAttempts)
        }
    }

    private func fetchVodStreams(timeout: TimeInterval = 30, maxAttempts: Int = 2) async throws -> [XtreamStream] {
        try await fetchArray(action: "get_vod_streams", timeout: timeout, maxAttempts: maxAttempts)
    }

    private func fetchSeries(timeout: TimeInterval = 30, maxAttempts: Int = 2) async throws -> [XtreamSeries] {
        try await fetchArray(action: "get_series", timeout: timeout, maxAttempts: maxAttempts)
    }

    private func fetchCategories(
        action: String,
        kind: ProviderCategoryKind,
        timeout: TimeInterval = 30,
        maxAttempts: Int = 2
    ) async throws -> [ProviderCategory] {
        let categories: [XtreamCategory] = try await fetchArray(action: action, timeout: timeout, maxAttempts: maxAttempts)
        return categories.compactMap { category in
            guard let id = category.categoryId, let name = category.categoryName else {
                return nil
            }
            return ProviderCategory(id: id, kind: kind, name: name)
        }
    }

    private func fetchOptionalCategories(action: String, kind: ProviderCategoryKind, mode: XtreamImportMode) async -> [ProviderCategory] {
        (try? await fetchCategories(
            action: action,
            kind: kind,
            timeout: mode.categoryRequestTimeout,
            maxAttempts: mode.optionalRequestAttempts
        )) ?? []
    }

    private func fetchOptionalVodStreams(mode: XtreamImportMode) async -> OptionalProviderResult<XtreamStream> {
        await optionalProviderResult {
            try await fetchVodStreams(timeout: mode.vodStreamRequestTimeout, maxAttempts: mode.optionalRequestAttempts)
        }
    }

    private func fetchOptionalSeries(mode: XtreamImportMode) async -> OptionalProviderResult<XtreamSeries> {
        await optionalProviderResult {
            try await fetchSeries(timeout: mode.seriesRequestTimeout, maxAttempts: mode.optionalRequestAttempts)
        }
    }

    private func optionalProviderResult<T>(_ operation: () async throws -> [T]) async -> OptionalProviderResult<T> {
        do {
            return OptionalProviderResult(items: try await operation(), didTimeOut: false)
        } catch let error as AppError where error.isTimeout {
            return OptionalProviderResult(items: [], didTimeOut: true)
        } catch let error as URLError where error.code == .timedOut {
            return OptionalProviderResult(items: [], didTimeOut: true)
        } catch {
            return OptionalProviderResult(items: [], didTimeOut: false)
        }
    }

    private func endpointHealth(
        name: String,
        action: String?,
        operation: () async throws -> Int
    ) async -> ProviderEndpointHealth {
        let start = Date()
        do {
            let count = try await operation()
            return ProviderEndpointHealth(
                name: name,
                status: count > 0 ? .ok : .empty,
                responseTime: Date().timeIntervalSince(start),
                itemCount: count,
                message: providerContext(for: action)
            )
        } catch let error as AppError where error.isTimeout {
            return ProviderEndpointHealth(
                name: name,
                status: .timedOut,
                responseTime: Date().timeIntervalSince(start),
                itemCount: nil,
                message: error.localizedDescription
            )
        } catch let error as URLError where error.code == .timedOut {
            return ProviderEndpointHealth(
                name: name,
                status: .timedOut,
                responseTime: Date().timeIntervalSince(start),
                itemCount: nil,
                message: error.localizedDescription
            )
        } catch {
            return ProviderEndpointHealth(
                name: name,
                status: .failed,
                responseTime: Date().timeIntervalSince(start),
                itemCount: nil,
                message: error.localizedDescription
            )
        }
    }

    private func playlistHealth() async -> ProviderEndpointHealth {
        await endpointHealth(name: "M3U Export", action: nil) {
            guard let request = playlistRequest(timeout: 10) else {
                throw AppError.invalidURL
            }

            let (data, response) = try await Self.data(for: request, context: "Provider M3U playlist", maxAttempts: 1)
            try validateHTTPResponse(response, context: "Provider M3U playlist")
            let text = try providerText(from: data, context: "Provider M3U playlist")
            return M3UParser.parse(text).count
        }
    }

    private func fetchM3UProviderLibrary(
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        categories: [ProviderCategory],
        timeout: TimeInterval = 45
    ) async throws -> ProviderImportResult {
        let requests = playlistRequests(timeout: timeout)
        guard !requests.isEmpty else {
            throw AppError.invalidURL
        }

        var lastError: Error?
        for request in requests {
            do {
                let result = try await importM3UProviderLibrary(
                    request: request,
                    sourceId: sourceId,
                    accountInfo: accountInfo,
                    categories: categories
                )
                if result.hasContent {
                    return result
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw AppError.emptyPlaylist
    }

    private func importM3UProviderLibrary(
        request: URLRequest,
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        categories: [ProviderCategory]
    ) async throws -> ProviderImportResult {
        do {
            let (data, response) = try await Self.downloadData(for: request, context: "Provider M3U playlist")
            try validateHTTPResponse(response, context: "Provider M3U playlist")
            let playlist = try providerText(from: data, context: "Provider M3U playlist")
            let parsed = M3UParser.parse(playlist)
            guard !parsed.isEmpty else {
                throw AppError.emptyPlaylist
            }

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
                seriesItems: [],
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

    private func fetchOptionalM3UProviderLibrary(
        sourceId: UUID,
        accountInfo: ProviderAccountInfo?,
        categories: [ProviderCategory],
        timeout: TimeInterval = 45
    ) async -> ProviderImportResult? {
        try? await fetchM3UProviderLibrary(
            sourceId: sourceId,
            accountInfo: accountInfo,
            categories: categories,
            timeout: timeout
        )
    }

    private func fetchSeriesEpisodes(
        sourceId: UUID,
        series: [XtreamSeries],
        categoryNames: [String: String]
    ) async throws -> [SeriesEpisode] {
        guard !series.isEmpty else {
            return []
        }

        var batches: [[XtreamSeries]] = []
        var batch: [XtreamSeries] = []
        batch.reserveCapacity(Self.seriesDetailConcurrencyLimit)

        for item in series {
            batch.append(item)
            if batch.count == Self.seriesDetailConcurrencyLimit {
                batches.append(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            batches.append(batch)
        }

        var episodes: [SeriesEpisode] = []
        for batch in batches {
            let batchEpisodes = await withTaskGroup(of: [SeriesEpisode].self) { group in
                for item in batch {
                    group.addTask {
                        await fetchSeriesEpisodes(
                            sourceId: sourceId,
                            item: item,
                            categoryNames: categoryNames,
                            fallbackCategory: nil
                        )
                    }
                }

                var result: [SeriesEpisode] = []
                for await itemEpisodes in group {
                    result.append(contentsOf: itemEpisodes)
                }
                return result
            }

            episodes.append(contentsOf: batchEpisodes)
        }

        return episodes
    }

    private func fetchSeriesEpisodes(
        sourceId: UUID,
        item: XtreamSeries,
        categoryNames: [String: String],
        fallbackCategory: String?
    ) async -> [SeriesEpisode] {
        // Some panels return incomplete series shells or fail individual series detail calls.
        // Skip those instead of failing the full provider import.
        guard let seriesId = item.seriesId else {
            return []
        }

        let info: XtreamSeriesInfo
        do {
            info = try await fetch(action: "get_series_info", extraQueryItems: [
                URLQueryItem(name: "series_id", value: "\(seriesId)")
            ])
        } catch {
            return []
        }

        var episodes: [SeriesEpisode] = []
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
                    category: categoryNames[item.categoryId ?? ""] ?? fallbackCategory ?? categoryFallback(item.categoryId, prefix: "Series"),
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

        return episodes
    }

    private func fetch<T: Decodable>(
        action: String?,
        extraQueryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 30,
        maxAttempts: Int = 2
    ) async throws -> T {
        guard let request = providerRequest(action: action, extraQueryItems: extraQueryItems, timeout: timeout) else {
            throw AppError.invalidURL
        }

        // All provider calls flow through this path so HTTP, network, and JSON errors stay user-readable.
        do {
            let (data, response) = try await Self.data(for: request, context: providerContext(for: action), maxAttempts: maxAttempts)
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
        extraQueryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 30,
        maxAttempts: Int = 2
    ) async throws -> [T] {
        guard let request = providerRequest(action: action, extraQueryItems: extraQueryItems, timeout: timeout) else {
            throw AppError.invalidURL
        }

        do {
            let (data, response) = try await Self.data(for: request, context: providerContext(for: action), maxAttempts: maxAttempts)
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

    private func providerRequest(action: String?, extraQueryItems: [URLQueryItem], timeout: TimeInterval) -> URLRequest? {
        let apiURL = providerBaseURL.appendingPathComponent("player_api.php")
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
        request.timeoutInterval = timeout
        for (field, value) in Self.providerAPIHTTPHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private func playlistRequest(timeout: TimeInterval = 45) -> URLRequest? {
        playlistRequest(output: "m3u8", timeout: timeout, headers: Self.mediaHTTPHeaders)
    }

    private func playlistRequests(timeout: TimeInterval = 45) -> [URLRequest] {
        let variants: [String?] = ["m3u8", "ts", nil]
        let headerVariants = [
            Self.mediaHTTPHeaders,
            Self.providerAPIHTTPHeaders
        ]

        return variants.flatMap { output in
            headerVariants.compactMap { headers in
                playlistRequest(output: output, timeout: timeout, headers: headers)
            }
        }
    }

    private func playlistRequest(output: String?, timeout: TimeInterval, headers: [String: String]) -> URLRequest? {
        let playlistURL = providerBaseURL.appendingPathComponent("get.php")
        var components = URLComponents(url: playlistURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "type", value: "m3u_plus")
        ]
        if let output {
            queryItems.append(URLQueryItem(name: "output", value: output))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        // Use the caller-supplied timeout. Playlist downloads need long timeouts (up to 240-300s)
        // for large M3U exports from slow providers. The previous min(timeout, 30) silently
        // ignored the caller's intent and caused playlist imports to time out on slow servers.
        request.timeoutInterval = timeout
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func mediaRequest(url: URL, timeout: TimeInterval = 45) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for (field, value) in mediaHTTPHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    static func data(for request: URLRequest, context: String, maxAttempts: Int = 2) async throws -> (Data, URLResponse) {
        var lastError: Error?
        let attempts = max(maxAttempts, 1)

        for attempt in 0..<attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   shouldRetry(statusCode: httpResponse.statusCode),
                   attempt + 1 < attempts {
                    try await retryDelay(attempt: attempt)
                    continue
                }

                return (data, response)
            } catch let error as URLError where shouldRetry(error) && attempt + 1 < attempts {
                lastError = error
                try await retryDelay(attempt: attempt)
            } catch {
                throw error
            }
        }

        if let lastError {
            throw lastError
        }

        throw AppError.importFailed("\(context) failed after retrying.")
    }

    static func downloadData(for request: URLRequest, context: String) async throws -> (Data, URLResponse) {
        let (fileURL, response) = try await playlistDownloadSession.download(for: request)
        do {
            return (try Data(contentsOf: fileURL), response)
        } catch {
            throw AppError.importFailed("\(context) could not be read after download. \(error.localizedDescription)")
        }
    }

    private static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    private static func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func retryDelay(attempt: Int) async throws {
        let nanoseconds = UInt64(attempt + 1) * 500_000_000
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    static var mediaHTTPHeaders: [String: String] {
        [
            "User-Agent": mediaUserAgent,
            "Accept": "*/*",
            "Connection": "keep-alive"
        ]
    }

    private static var providerAPIHTTPHeaders: [String: String] {
        [
            "User-Agent": providerAPIUserAgent,
            "Accept": "application/json, text/plain, */*",
            "Connection": "keep-alive"
        ]
    }

    private static let providerAPIUserAgent = "GSE SMART IPTV"
    private static let mediaUserAgent = "VLC/3.0.21 LibVLC/3.0.21"

    private static let playlistDownloadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpShouldUsePipelining = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 240
        configuration.timeoutIntervalForResource = 300
        configuration.urlCache = nil
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private func providerText(from data: Data, context: String) throws -> String {
        guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AppError.importFailed("\(context) could not be read as text.")
        }
        return value
    }

    static func decodeProviderArray<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()

        // Fast path: peek at the first non-whitespace byte to avoid decoding the full payload
        // as an array when the response is clearly an object, and vice versa.
        // This eliminates up to 2 unnecessary full-decode attempts on 50k+ item provider lists.
        let firstByte = data.first {
            $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\n") && $0 != UInt8(ascii: "\r") && $0 != UInt8(ascii: "\t")
        }

        if firstByte == UInt8(ascii: "[") {
            if let direct = try? decoder.decode([T].self, from: data) {
                return direct
            }
        }

        if firstByte == UInt8(ascii: "{") || firstByte == nil {
            if let keyed = try? decoder.decode([String: T].self, from: data) {
                return keyed
                    .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                    .map(\.value)
            }
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

    func streamURL(path: String, streamId: Int, extensionValue: String) -> String {
        providerBaseURL
            .appendingPathComponent(path)
            .appendingPathComponent(username)
            .appendingPathComponent(password)
            .appendingPathComponent("\(streamId).\(extensionValue)")
            .absoluteString
    }

    private var providerBaseURL: URL {
        if serverURL.lastPathComponent.localizedCaseInsensitiveCompare("player_api.php") == .orderedSame
            || serverURL.lastPathComponent.localizedCaseInsensitiveCompare("get.php") == .orderedSame {
            return serverURL.deletingLastPathComponent()
        }

        return serverURL
    }

    private func categoryFallback(_ categoryId: String?, prefix: String) -> String {
        guard let categoryId, !categoryId.isEmpty else {
            return prefix
        }
        return "\(prefix) \(categoryId)"
    }
}

private extension AppError {
    var isTimeout: Bool {
        switch self {
        case .networkUnavailable(let message), .importFailed(let message):
            return message.localizedCaseInsensitiveContains("timed out")
                || message.localizedCaseInsensitiveContains("timeout")
        default:
            return false
        }
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

    init(seriesId: Int?, name: String?, cover: String?, categoryId: String?) {
        self.seriesId = seriesId
        self.name = name
        self.cover = cover
        self.categoryId = categoryId
    }

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
