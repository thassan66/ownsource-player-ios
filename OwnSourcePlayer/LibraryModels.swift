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

struct SeriesItem: Identifiable, Codable, Hashable {
    var id: UUID
    var sourceId: UUID
    var title: String
    var category: String
    var posterURL: String?
    var providerSeriesId: Int?
    var episodeCount: Int?
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        sourceId: UUID,
        title: String,
        category: String,
        posterURL: String? = nil,
        providerSeriesId: Int? = nil,
        episodeCount: Int? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.category = category.isEmpty ? "Series" : category
        self.posterURL = posterURL
        self.providerSeriesId = providerSeriesId
        self.episodeCount = episodeCount
        self.isFavorite = isFavorite
    }

    var placeholderChannel: Channel {
        Channel(
            id: id,
            sourceId: sourceId,
            name: title,
            streamURL: "about:blank",
            category: category,
            mediaKind: .seriesEpisode,
            logoURL: posterURL,
            isFavorite: isFavorite
        )
    }
}

struct MediaLibrary: Codable, Hashable {
    var liveChannels: [LiveChannel]
    var movies: [MovieItem]
    var seriesItems: [SeriesItem]
    var seriesEpisodes: [SeriesEpisode]

    enum CodingKeys: String, CodingKey {
        case liveChannels
        case movies
        case seriesItems
        case seriesEpisodes
    }

    init(
        liveChannels: [LiveChannel] = [],
        movies: [MovieItem] = [],
        seriesItems: [SeriesItem] = [],
        seriesEpisodes: [SeriesEpisode] = []
    ) {
        self.liveChannels = liveChannels
        self.movies = movies
        self.seriesItems = seriesItems
        self.seriesEpisodes = seriesEpisodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveChannels = try container.decodeIfPresent([LiveChannel].self, forKey: .liveChannels) ?? []
        movies = try container.decodeIfPresent([MovieItem].self, forKey: .movies) ?? []
        seriesItems = try container.decodeIfPresent([SeriesItem].self, forKey: .seriesItems) ?? []
        seriesEpisodes = try container.decodeIfPresent([SeriesEpisode].self, forKey: .seriesEpisodes) ?? []
    }

    var allChannels: [Channel] {
        liveChannels.map(\.channel)
            + movies.map(\.channel)
            + seriesEpisodes.map(\.channel)
    }

    var count: Int {
        liveChannels.count + movies.count + seriesItems.count + seriesEpisodes.count
    }

    static func from(channels: [Channel]) -> MediaLibrary {
        var library = MediaLibrary()
        for channel in channels {
            switch channel.mediaKind {
            case .live:
                library.liveChannels.append(LiveChannel(channel: channel))
            case .movie:
                library.movies.append(MovieItem(channel: channel))
            case .seriesEpisode:
                library.seriesEpisodes.append(SeriesEpisode(channel: channel))
            }
        }
        return library
    }

    func removingSource(_ sourceId: UUID) -> MediaLibrary {
        MediaLibrary(
            liveChannels: liveChannels.filter { $0.sourceId != sourceId },
            movies: movies.filter { $0.sourceId != sourceId },
            seriesItems: seriesItems.filter { $0.sourceId != sourceId },
            seriesEpisodes: seriesEpisodes.filter { $0.sourceId != sourceId }
        )
    }

    func replacingSource(_ sourceId: UUID, with channels: [Channel]) -> MediaLibrary {
        let retained = removingSource(sourceId)
        let imported = MediaLibrary.from(channels: channels)
        return MediaLibrary(
            liveChannels: retained.liveChannels + imported.liveChannels,
            movies: retained.movies + imported.movies,
            seriesItems: retained.seriesItems,
            seriesEpisodes: retained.seriesEpisodes + imported.seriesEpisodes
        )
    }

    func replacingSource(_ sourceId: UUID, with importResult: ProviderImportResult) -> MediaLibrary {
        let retained = removingSource(sourceId)
        return MediaLibrary(
            liveChannels: retained.liveChannels + importResult.liveChannels,
            movies: retained.movies + importResult.movies,
            seriesItems: retained.seriesItems + importResult.seriesItems,
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
        } else if let index = updated.seriesItems.firstIndex(where: { $0.id == channelId }) {
            updated.seriesItems[index].isFavorite.toggle()
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

    func repairingXtreamPlaybackURLs() -> MediaLibrary {
        var updated = self
        updated.liveChannels = liveChannels.map { item in
            var value = item
            value.streamURL = Self.repairedXtreamPlaybackURL(value.streamURL)
            return value
        }
        updated.movies = movies.map { item in
            var value = item
            value.streamURL = Self.repairedXtreamPlaybackURL(value.streamURL)
            return value
        }
        updated.seriesEpisodes = seriesEpisodes.map { item in
            var value = item
            value.streamURL = Self.repairedXtreamPlaybackURL(value.streamURL)
            return value
        }
        return updated
    }

    private static func repairedXtreamPlaybackURL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/player_api.php/live/", with: "/live/")
            .replacingOccurrences(of: "/player_api.php/movie/", with: "/movie/")
            .replacingOccurrences(of: "/player_api.php/series/", with: "/series/")
            .replacingOccurrences(of: "/get.php/live/", with: "/live/")
            .replacingOccurrences(of: "/get.php/movie/", with: "/movie/")
            .replacingOccurrences(of: "/get.php/series/", with: "/series/")
    }
}

enum LibraryBrowserKind: Equatable {
    case live
    case videos
}

struct LibraryQueryResult<Item> {
    var items: [Item]
    var totalCount: Int
    var isLimited: Bool
}

struct MediaLibraryIndex {
    static let defaultLimit = 120

    private var allRefs: [LibraryItemRef] = []
    private var liveRefs: [LibraryItemRef] = []
    private var videoRefs: [LibraryItemRef] = []
    private var movieRefs: [LibraryItemRef] = []
    private var seriesRefs: [LibraryItemRef] = []
    private var favoriteRefs: [LibraryItemRef] = []
    private var recentlyWatchedRefs: [LibraryItemRef] = []
    private var recentlyAddedRefs: [LibraryItemRef] = []
    private var liveCategoryRefs: [String: [LibraryItemRef]] = [:]
    private var videoCategoryRefs: [String: [LibraryItemRef]] = [:]
    private var movieCategoryRefs: [String: [LibraryItemRef]] = [:]
    private var seriesCategoryRefs: [String: [LibraryItemRef]] = [:]
    private var normalizedSearchTextByRef: [LibraryItemRef: String] = [:]
    private var refById: [UUID: LibraryItemRef] = [:]
    private var ids: Set<UUID> = []

    var liveCategories: [String] = []
    var videoCategories: [String] = []
    var movieCategories: [String] = []
    var seriesCategories: [String] = []
    var allCategories: [String] = []

    init(library: MediaLibrary = MediaLibrary()) {
        liveRefs = library.liveChannels.indices.map { .live($0) }
        movieRefs = library.movies.indices.map { .movie($0) }
        seriesRefs = library.seriesEpisodes.indices.map { .series($0) }
        videoRefs = movieRefs + seriesRefs
        allRefs = liveRefs + videoRefs
        let insertionRefs = allRefs

        ids = Set(allRefs.map { $0.id(in: library) })
        refById = allRefs.reduce(into: [UUID: LibraryItemRef]()) { result, ref in
            result[ref.id(in: library)] = ref
        }
        normalizedSearchTextByRef = allRefs.reduce(into: [LibraryItemRef: String]()) { result, ref in
            result[ref] = normalized(ref.searchText(in: library))
        }
        favoriteRefs = allRefs.filter { $0.isFavorite(in: library) }
        recentlyWatchedRefs = allRefs
            .filter { $0.lastWatchedAt(in: library) != nil }
            .sorted { ($0.lastWatchedAt(in: library) ?? .distantPast) > ($1.lastWatchedAt(in: library) ?? .distantPast) }
        recentlyAddedRefs = Array(insertionRefs.reversed())

        liveCategoryRefs = groupedByCategory(liveRefs, in: library)
        videoCategoryRefs = groupedByCategory(videoRefs, in: library)
        movieCategoryRefs = groupedByCategory(movieRefs, in: library)
        seriesCategoryRefs = groupedByCategory(seriesRefs, in: library)
        liveCategories = sortedCategories(liveCategoryRefs)
        videoCategories = sortedCategories(videoCategoryRefs)
        movieCategories = sortedCategories(movieCategoryRefs)
        seriesCategories = sortedCategories(seriesCategoryRefs)
        allCategories = Array(Set(liveCategories + videoCategories + movieCategories + seriesCategories)).sorted()
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }

    func categoryCount(kind: LibraryBrowserKind, category: String) -> Int {
        switch kind {
        case .live:
            return count(baseRefs: liveRefs, categoryRefs: liveCategoryRefs, category: category)
        case .videos:
            return count(baseRefs: videoRefs, categoryRefs: videoCategoryRefs, category: category)
        }
    }

    func movieCategoryCount(_ category: String) -> Int {
        count(baseRefs: movieRefs, categoryRefs: movieCategoryRefs, category: category)
    }

    func seriesCategoryCount(_ category: String) -> Int {
        count(baseRefs: seriesRefs, categoryRefs: seriesCategoryRefs, category: category)
    }

    mutating func updateFavorite(channelId: UUID, in library: MediaLibrary) {
        guard let ref = refById[channelId] else {
            return
        }

        favoriteRefs.removeAll { $0 == ref }
        if ref.isFavorite(in: library) {
            favoriteRefs.insert(ref, at: 0)
        }
    }

    mutating func updateRecentlyWatched(channelId: UUID, in library: MediaLibrary) {
        guard let ref = refById[channelId],
              ref.lastWatchedAt(in: library) != nil else {
            return
        }

        recentlyWatchedRefs.removeAll { $0 == ref }
        recentlyWatchedRefs.insert(ref, at: 0)
    }

    func favoriteChannels(
        in library: MediaLibrary,
        canShow: (Channel) -> Bool,
        limit: Int = 100
    ) -> [Channel] {
        collectChannels(from: favoriteRefs, in: library, searchText: "", canShow: canShow, limit: limit).items
    }

    func recentlyWatchedChannels(
        in library: MediaLibrary,
        canShow: (Channel) -> Bool,
        limit: Int = 100
    ) -> [Channel] {
        collectChannels(from: recentlyWatchedRefs, in: library, searchText: "", canShow: canShow, limit: limit).items
    }

    func recentlyAddedChannels(
        in library: MediaLibrary,
        canShow: (Channel) -> Bool,
        limit: Int = 24
    ) -> [Channel] {
        collectChannels(from: Array(recentlyAddedRefs), in: library, searchText: "", canShow: canShow, limit: limit).items
    }

    func liveNowCandidates(
        in library: MediaLibrary,
        canShow: (Channel) -> Bool,
        limit: Int = 24
    ) -> [Channel] {
        collectChannels(from: liveRefs, in: library, searchText: "", canShow: canShow, limit: limit).items
    }

    func channels(
        in library: MediaLibrary,
        kind: LibraryBrowserKind,
        category: String,
        searchText: String,
        canShow: (Channel) -> Bool,
        limit: Int = defaultLimit
    ) -> LibraryQueryResult<Channel> {
        let refs = candidateRefs(kind: kind, category: category, searchText: searchText)
        return collectChannels(from: refs, in: library, searchText: searchText, canShow: canShow, limit: limit)
    }

    func movies(
        in library: MediaLibrary,
        category: String,
        searchText: String,
        canShow: (Channel) -> Bool,
        limit: Int = defaultLimit
    ) -> LibraryQueryResult<MovieItem> {
        let refs = candidateRefs(
            baseRefs: movieRefs,
            categoryRefs: movieCategoryRefs,
            category: category,
            searchText: searchText
        )
        var items: [MovieItem] = []
        var isLimited = false
        let normalizedSearch = normalized(searchText)

        for ref in refs {
            guard case .movie(let index) = ref else {
                continue
            }
            let item = library.movies[index]
            guard canShow(item.channel), matches(ref, searchText: normalizedSearch, in: library) else {
                continue
            }
            guard items.count < limit else {
                isLimited = true
                break
            }
            items.append(item)
        }

        return LibraryQueryResult(items: items, totalCount: refs.count, isLimited: isLimited || refs.count > items.count)
    }

    func seriesEpisodes(
        in library: MediaLibrary,
        category: String,
        searchText: String,
        canShow: (Channel) -> Bool,
        limit: Int = defaultLimit
    ) -> LibraryQueryResult<SeriesEpisode> {
        let refs = candidateRefs(
            baseRefs: seriesRefs,
            categoryRefs: seriesCategoryRefs,
            category: category,
            searchText: searchText
        )
        var items: [SeriesEpisode] = []
        var isLimited = false
        let normalizedSearch = normalized(searchText)

        for ref in refs {
            guard case .series(let index) = ref else {
                continue
            }
            let item = library.seriesEpisodes[index]
            guard canShow(item.channel), matches(ref, searchText: normalizedSearch, in: library) else {
                continue
            }
            guard items.count < limit else {
                isLimited = true
                break
            }
            items.append(item)
        }

        return LibraryQueryResult(items: items, totalCount: refs.count, isLimited: isLimited || refs.count > items.count)
    }

    private func candidateRefs(kind: LibraryBrowserKind, category: String, searchText: String) -> [LibraryItemRef] {
        switch kind {
        case .live:
            return candidateRefs(
                baseRefs: liveRefs,
                categoryRefs: liveCategoryRefs,
                category: category,
                searchText: searchText
            )
        case .videos:
            return candidateRefs(
                baseRefs: videoRefs,
                categoryRefs: videoCategoryRefs,
                category: category,
                searchText: searchText
            )
        }
    }

    private func candidateRefs(
        baseRefs: [LibraryItemRef],
        categoryRefs: [String: [LibraryItemRef]],
        category: String,
        searchText: String
    ) -> [LibraryItemRef] {
        if category == "Favorites" {
            let baseSet = Set(baseRefs)
            return favoriteRefs.filter { baseSet.contains($0) }
        }
        return category == "All" ? baseRefs : categoryRefs[category] ?? []
    }

    private func count(
        baseRefs: [LibraryItemRef],
        categoryRefs: [String: [LibraryItemRef]],
        category: String
    ) -> Int {
        if category == "All" {
            return baseRefs.count
        }

        if category == "Favorites" {
            let baseSet = Set(baseRefs)
            return favoriteRefs.reduce(into: 0) { count, ref in
                if baseSet.contains(ref) {
                    count += 1
                }
            }
        }

        return categoryRefs[category]?.count ?? 0
    }

    private func collectChannels(
        from refs: [LibraryItemRef],
        in library: MediaLibrary,
        searchText: String,
        canShow: (Channel) -> Bool,
        limit: Int
    ) -> LibraryQueryResult<Channel> {
        var items: [Channel] = []
        var isLimited = false
        let normalizedSearch = normalized(searchText)

        for ref in refs {
            let channel = ref.channel(in: library)
            guard canShow(channel), matches(ref, searchText: normalizedSearch, in: library) else {
                continue
            }
            guard items.count < limit else {
                isLimited = true
                break
            }
            items.append(channel)
        }

        return LibraryQueryResult(items: items, totalCount: refs.count, isLimited: isLimited || refs.count > items.count)
    }

    private func matches(_ ref: LibraryItemRef, searchText: String, in library: MediaLibrary) -> Bool {
        searchText.isEmpty || (normalizedSearchTextByRef[ref] ?? normalized(ref.searchText(in: library))).contains(searchText)
    }

    private func groupedByCategory(_ refs: [LibraryItemRef], in library: MediaLibrary) -> [String: [LibraryItemRef]] {
        refs.reduce(into: [String: [LibraryItemRef]]()) { result, ref in
            result[ref.category(in: library), default: []].append(ref)
        }
    }

    private func sortedCategories(_ values: [String: [LibraryItemRef]]) -> [String] {
        values.keys.sorted()
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LibraryItemRef: Hashable {
    case live(Int)
    case movie(Int)
    case series(Int)

    func id(in library: MediaLibrary) -> UUID {
        switch self {
        case .live(let index):
            return library.liveChannels[index].id
        case .movie(let index):
            return library.movies[index].id
        case .series(let index):
            return library.seriesEpisodes[index].id
        }
    }

    func channel(in library: MediaLibrary) -> Channel {
        switch self {
        case .live(let index):
            return library.liveChannels[index].channel
        case .movie(let index):
            return library.movies[index].channel
        case .series(let index):
            return library.seriesEpisodes[index].channel
        }
    }

    func name(in library: MediaLibrary) -> String {
        switch self {
        case .live(let index):
            return library.liveChannels[index].name
        case .movie(let index):
            return library.movies[index].title
        case .series(let index):
            return library.seriesEpisodes[index].title
        }
    }

    func category(in library: MediaLibrary) -> String {
        switch self {
        case .live(let index):
            return library.liveChannels[index].category
        case .movie(let index):
            return library.movies[index].category
        case .series(let index):
            return library.seriesEpisodes[index].category
        }
    }

    func isFavorite(in library: MediaLibrary) -> Bool {
        switch self {
        case .live(let index):
            return library.liveChannels[index].isFavorite
        case .movie(let index):
            return library.movies[index].isFavorite
        case .series(let index):
            return library.seriesEpisodes[index].isFavorite
        }
    }

    func lastWatchedAt(in library: MediaLibrary) -> Date? {
        switch self {
        case .live(let index):
            return library.liveChannels[index].lastWatchedAt
        case .movie(let index):
            return library.movies[index].lastWatchedAt
        case .series(let index):
            return library.seriesEpisodes[index].lastWatchedAt
        }
    }

    func searchText(in library: MediaLibrary) -> String {
        searchTokens(in: library).joined(separator: " ").lowercased()
    }

    func searchTokens(in library: MediaLibrary) -> [String] {
        switch self {
        case .live(let index):
            let item = library.liveChannels[index]
            return [item.name, item.category, item.tvgId].compactMap { $0 }
        case .movie(let index):
            let item = library.movies[index]
            return [item.title, item.category, item.releaseYear].compactMap { $0 }
        case .series(let index):
            let item = library.seriesEpisodes[index]
            return [item.title, item.seriesTitle, item.category].compactMap { $0 }
        }
    }
}

struct ProviderImportResult: Codable, Hashable {
    var account: ProviderAccountInfo?
    var categories: [ProviderCategory]
    var liveChannels: [LiveChannel]
    var movies: [MovieItem]
    var seriesItems: [SeriesItem]
    var seriesEpisodes: [SeriesEpisode]

    var hasContent: Bool {
        !liveChannels.isEmpty || !movies.isEmpty || !seriesItems.isEmpty || !seriesEpisodes.isEmpty
    }

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
        // Many Xtream panels return different status values: "Active", "Enabled", "Trial",
        // "1", "true", or nothing at all. Nil defaults to active (no status = no restriction).
        guard let status else { return true }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeValues: Set<String> = ["active", "enabled", "trial", "1", "true", "yes", "ok"]
        return activeValues.contains(normalized)
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
