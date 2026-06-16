import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sources: [MediaSource] = []
    @Published private(set) var library = MediaLibrary()
    @Published private(set) var libraryIndex = MediaLibraryIndex()
    @Published private(set) var epgPrograms: [EPGProgram] = [] {
        didSet { rebuildEPGIndex() }
    }
    /// O(1) lookup from tvg-id → currently-airing EPGProgram. Rebuilt whenever epgPrograms changes.
    private(set) var epgIndex: [String: EPGProgram] = [:]
    @Published private(set) var epgGuideSource: EPGGuideSource?
    @Published var hasAcceptedTerms: Bool {
        didSet { defaults.set(hasAcceptedTerms, forKey: Keys.hasAcceptedTerms) }
    }
    @Published var parentalPIN: String {
        didSet { persistParentalPIN() }
    }
    @Published var protectedCategories: Set<String> {
        didSet { encode(Array(protectedCategories), key: Keys.protectedCategories) }
    }
    @Published var isParentalUnlocked = false
    @Published var selectedTheme: AppTheme {
        didSet { defaults.set(selectedTheme.rawValue, forKey: Keys.selectedTheme) }
    }
    @Published var playbackEnginePreference: PlaybackEnginePreference {
        didSet { defaults.set(playbackEnginePreference.rawValue, forKey: Keys.playbackEnginePreference) }
    }
    @Published var isLoading = false
    @Published var loadingMessage = "Loading..."
    @Published var alertMessage: String?
    @Published private(set) var providerHealthReports: [UUID: ProviderHealthReport] = [:]
    @Published private(set) var providerHealthChecksInProgress: Set<UUID> = []
    @Published private(set) var seriesEpisodeLoadsInProgress: Set<Int> = []

    private let defaults = UserDefaults.standard
    private let libraryStore = LibraryPersistenceStore()
    private var pendingPersistTask: Task<Void, Never>?
    private var providerEnrichmentTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        hasAcceptedTerms = defaults.bool(forKey: Keys.hasAcceptedTerms)
        let keychainPIN = try? KeychainStore.parentalPIN()
        let legacyPIN = defaults.string(forKey: Keys.parentalPIN)
        parentalPIN = keychainPIN ?? legacyPIN ?? ""
        protectedCategories = Set(Self.decode([String].self, key: Keys.protectedCategories, defaults: defaults) ?? [])
        selectedTheme = AppTheme(rawValue: defaults.string(forKey: Keys.selectedTheme) ?? "") ?? .system
        playbackEnginePreference = PlaybackEnginePreference(rawValue: defaults.string(forKey: Keys.playbackEnginePreference) ?? "") ?? .automatic
        if keychainPIN == nil, legacyPIN?.isEmpty == false {
            persistParentalPIN()
        }
        defaults.removeObject(forKey: Keys.parentalPIN)
        Task {
            await load()
        }
    }

    var favoriteChannels: [Channel] {
        libraryIndex.favoriteChannels(in: library, canShow: canShow)
    }

    var recentlyWatched: [Channel] {
        libraryIndex.recentlyWatchedChannels(in: library, canShow: canShow)
    }

    func categories(for kind: LibraryBrowserKind) -> [String] {
        let values = kind == .live ? libraryIndex.liveCategories : libraryIndex.videoCategories
        return ["All", "Favorites"] + values
    }

    func movieCategories() -> [String] {
        ["All", "Favorites"] + libraryIndex.movieCategories
    }

    func seriesCategories() -> [String] {
        if !library.seriesItems.isEmpty {
            let values = Array(Set(library.seriesItems.map(\.category))).sorted()
            return ["All", "Favorites"] + values
        }
        return ["All", "Favorites"] + libraryIndex.seriesCategories
    }

    func protectableCategories() -> [String] {
        libraryIndex.allCategories
    }

    func categoryCount(for kind: LibraryBrowserKind, category: String) -> Int {
        libraryIndex.categoryCount(kind: kind, category: category)
    }

    func movieCategoryCount(_ category: String) -> Int {
        libraryIndex.movieCategoryCount(category)
    }

    func seriesCategoryCount(_ category: String) -> Int {
        if !library.seriesItems.isEmpty {
            switch category {
            case "All":
                return library.seriesItems.count
            case "Favorites":
                return library.seriesItems.filter(\.isFavorite).count
            default:
                return library.seriesItems.filter { $0.category == category }.count
            }
        }
        return libraryIndex.seriesCategoryCount(category)
    }

    func browserChannels(kind: LibraryBrowserKind, category: String, searchText: String) -> LibraryQueryResult<Channel> {
        libraryIndex.channels(in: library, kind: kind, category: category, searchText: searchText, canShow: canShow)
    }

    func movies(category: String, searchText: String) -> LibraryQueryResult<MovieItem> {
        libraryIndex.movies(in: library, category: category, searchText: searchText, canShow: { canShow($0) })
    }

    func seriesEpisodes(category: String, searchText: String) -> LibraryQueryResult<SeriesEpisode> {
        libraryIndex.seriesEpisodes(in: library, category: category, searchText: searchText, canShow: { canShow($0) })
    }

    func seriesItems(category: String, searchText: String) -> LibraryQueryResult<SeriesItem> {
        let normalizedSearch = searchText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceItems = library.seriesItems.isEmpty ? seriesItemsFromEpisodes() : library.seriesItems
        let filtered = sourceItems.filter { item in
            let categoryMatches = category == "All"
                || item.category == category
                || (category == "Favorites" && item.isFavorite)
            let searchTokens = [item.title, item.category]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return categoryMatches && (normalizedSearch.isEmpty || searchTokens.contains(normalizedSearch))
        }
        let limit = MediaLibraryIndex.defaultLimit
        return LibraryQueryResult(
            items: Array(filtered.prefix(limit)),
            totalCount: filtered.count,
            isLimited: filtered.count > limit
        )
    }

    func episodes(for series: SeriesItem) -> [SeriesEpisode] {
        library.seriesEpisodes
            .filter { episode in
                if let providerSeriesId = series.providerSeriesId {
                    return episode.providerSeriesId == providerSeriesId && episode.sourceId == series.sourceId
                }
                return episode.sourceId == series.sourceId && (episode.seriesTitle ?? episode.category) == series.title
            }
            .sorted(by: episodeSort)
    }

    func isLoadingEpisodes(for series: SeriesItem) -> Bool {
        guard let providerSeriesId = series.providerSeriesId else {
            return false
        }
        return seriesEpisodeLoadsInProgress.contains(providerSeriesId)
    }

    func loadEpisodesIfNeeded(for series: SeriesItem) async {
        guard let providerSeriesId = series.providerSeriesId,
              episodes(for: series).isEmpty,
              !seriesEpisodeLoadsInProgress.contains(providerSeriesId),
              let source = sources.first(where: { $0.id == series.sourceId }),
              let serverURL = MediaURLValidator.httpURL(from: source.location) else {
            return
        }

        do {
            guard let credentials = try providerCredentials(for: source) else {
                throw AppError.missingCredentials
            }

            seriesEpisodeLoadsInProgress.insert(providerSeriesId)
            defer {
                seriesEpisodeLoadsInProgress.remove(providerSeriesId)
            }

            let client = XtreamClient(
                serverURL: serverURL,
                username: credentials.username,
                password: credentials.password
            )
            let episodes = try await client.fetchEpisodes(for: series)
            guard !episodes.isEmpty else {
                return
            }
            try await mergeSeriesEpisodes(episodes, sourceId: source.id)
        } catch {
            present(error)
        }
    }

    func recentlyAdded(limit: Int = 12) -> [Channel] {
        libraryIndex.recentlyAddedChannels(in: library, canShow: canShow, limit: limit)
    }

    func liveNowCandidates(limit: Int = 24) -> [Channel] {
        libraryIndex.liveNowCandidates(in: library, canShow: canShow, limit: limit)
    }

    func importRemoteSource(name: String, urlString: String) async {
        guard let url = MediaURLValidator.httpURL(from: urlString) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        beginLoading("Fetching playlist...")
        defer { endLoading() }

        do {
            let playlist = try await remoteText(from: url, context: "Playlist import")
            loadingMessage = "Parsing playlist..."
            let parsed = await parsePlaylist(playlist)
            let source = MediaSource(name: cleanName(name, fallback: url.host ?? "Playlist"), kind: .m3uURL, location: url.absoluteString, lastRefreshAt: Date())
            loadingMessage = "Indexing library..."
            try await saveImport(source: source, parsed: parsed)
        } catch {
            present(error)
        }
    }

    func importLocalFile(url: URL) async {
        let ext = url.pathExtension.lowercased()
        guard ["m3u", "m3u8", "txt"].contains(ext) else {
            alertMessage = AppError.unsupportedFile.localizedDescription
            return
        }

        beginLoading("Reading playlist file...")
        defer { endLoading() }

        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard didStartAccessing || FileManager.default.isReadableFile(atPath: url.path) else {
                throw AppError.fileAccessDenied
            }

            let data = try Data(contentsOf: url)
            let playlist = try text(from: data, context: "Playlist file")
            loadingMessage = "Parsing playlist..."
            let parsed = await parsePlaylist(playlist)

            let source = MediaSource(name: url.deletingPathExtension().lastPathComponent, kind: .m3uFile, location: url.lastPathComponent, lastRefreshAt: Date())
            loadingMessage = "Indexing library..."
            try await saveImport(source: source, parsed: parsed)
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            present(AppError.fileAccessDenied)
        } catch {
            present(error)
        }
    }

    func importXtreamSource(name: String, server: String, username: String, password: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            alertMessage = AppError.missingCredentials.localizedDescription
            return
        }

        guard let serverURL = MediaURLValidator.httpURL(from: server) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        beginLoading("Connecting to provider...")
        defer { endLoading() }

        do {
            let existingSource = existingXtreamSource(for: serverURL)
            let sourceName = cleanName(
                name,
                fallback: existingSource?.name ?? serverURL.host ?? "Media Source"
            )
            let source = MediaSource(
                id: existingSource?.id ?? UUID(),
                name: sourceName,
                kind: .xtream,
                location: serverURL.absoluteString,
                createdAt: existingSource?.createdAt ?? Date(),
                lastRefreshAt: Date()
            )
            let credentials = ProviderCredentials(username: trimmedUsername, password: trimmedPassword)
            let client = XtreamClient(serverURL: serverURL, username: trimmedUsername, password: trimmedPassword)

            loadingMessage = "Loading provider catalog..."
            let importResult = try await client.fetchProviderLibrary(sourceId: source.id, mode: .fast)

            loadingMessage = "Saving credentials..."
            try KeychainStore.save(credentials, for: source.id)

            loadingMessage = "Indexing provider library..."
            try await saveProviderImport(source: source, importResult: importResult)
            scheduleProviderEnrichment(source: source, credentials: credentials)
        } catch {
            present(error)
        }
    }

    func importEPG(urlString: String) async {
        guard let url = MediaURLValidator.httpURL(from: urlString) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        await loadEPG(from: url, urlString: url.absoluteString)
    }

    func refreshEPG() async {
        guard let guide = epgGuideSource,
              let url = MediaURLValidator.httpURL(from: guide.urlString) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        await loadEPG(from: url, urlString: guide.urlString)
    }

    func clearEPG() {
        epgPrograms = []
        epgGuideSource = nil
        persistLibrary()
    }

    func loadDemoLibrary() {
        let demoLibrary = DemoLibraryFactory.make()
        let source = demoLibrary.source

        sources.removeAll { $0.id == source.id || $0.name == source.name }
        sources.append(source)
        sources.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        setLibrary(library.replacingSource(source.id, with: demoLibrary.channels))
        epgPrograms = demoLibrary.programs
        epgGuideSource = demoLibrary.guideSource
        hasAcceptedTerms = true
        persistLibrary()
    }

    private func loadEPG(from url: URL, urlString: String) async {
        beginLoading("Fetching guide...")
        defer { endLoading() }

        do {
            let xml = try await remoteText(from: url, context: "Guide import")
            loadingMessage = "Parsing guide..."
            // Run the heavy regex-based XMLTV parse off the main thread (same pattern as M3U parsing).
            let programs = await Task.detached(priority: .userInitiated) {
                XMLTVParser.parse(xml)
            }.value
            guard !programs.isEmpty else {
                throw AppError.importFailed("No EPG programmes were found.")
            }

            epgPrograms = programs
            epgGuideSource = EPGGuideSource(urlString: urlString, lastRefreshAt: Date())
            persistLibrary()
        } catch {
            present(error)
        }
    }

    func refresh(source: MediaSource) async {
        if source.kind == .xtream {
            await refreshXtream(source: source)
            return
        }

        guard source.kind == .m3uURL else {
            alertMessage = "Local files cannot be refreshed automatically. Import the file again to update it."
            return
        }

        guard let url = MediaURLValidator.httpURL(from: source.location) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        beginLoading("Refreshing playlist...")
        defer { endLoading() }

        do {
            let playlist = try await remoteText(from: url, context: "Playlist refresh")
            loadingMessage = "Parsing playlist..."
            let parsed = await parsePlaylist(playlist)
            var refreshed = source
            refreshed.lastRefreshAt = Date()
            loadingMessage = "Indexing library..."
            try await saveImport(source: refreshed, parsed: parsed)
        } catch {
            present(error)
        }
    }

    func deleteSource(_ source: MediaSource) {
        providerEnrichmentTasks[source.id]?.cancel()
        providerEnrichmentTasks[source.id] = nil
        providerHealthReports[source.id] = nil
        sources.removeAll { $0.id == source.id }
        setLibrary(library.removingSource(source.id))
        KeychainStore.deleteCredentials(for: source.id)
        persistLibrary()
    }

    func toggleFavorite(_ channel: Channel) {
        guard libraryIndex.contains(channel.id) else {
            return
        }

        library = library.updatingFavorite(channelId: channel.id)
        libraryIndex.updateFavorite(channelId: channel.id, in: library)
        persistLibrary()
    }

    func markWatched(_ channel: Channel) {
        guard libraryIndex.contains(channel.id) else {
            return
        }

        library = library.markingWatched(channelId: channel.id)
        libraryIndex.updateRecentlyWatched(channelId: channel.id, in: library)
        schedulePersistLibrary()
    }

    func updateResumePosition(for channel: Channel, seconds: Double, persistImmediately: Bool = false) {
        guard channel.isOnDemand,
              seconds.isFinite,
              libraryIndex.contains(channel.id) else {
            return
        }

        library = library.updatingResumePosition(channelId: channel.id, seconds: seconds)
        libraryIndex.updateRecentlyWatched(channelId: channel.id, in: library)
        if persistImmediately {
            persistLibrary()
        } else {
            schedulePersistLibrary()
        }
    }

    func clearAllData() {
        providerEnrichmentTasks.values.forEach { $0.cancel() }
        providerEnrichmentTasks.removeAll()
        sources.forEach { KeychainStore.deleteCredentials(for: $0.id) }
        sources = []
        setLibrary(MediaLibrary())
        epgPrograms = []
        epgGuideSource = nil
        providerHealthReports = [:]
        hasAcceptedTerms = false
        parentalPIN = ""
        protectedCategories = []
        isParentalUnlocked = false
        removeLegacyLibraryDefaults()
        persistLibrary()
    }

    func isRestricted(_ channel: Channel) -> Bool {
        return parentalService().isRestricted(channel)
    }

    func canShow(_ channel: Channel) -> Bool {
        return parentalService().canShow(channel)
    }

    func unlockParentalControls(pin: String) -> Bool {
        guard parentalService().unlock(with: pin) else {
            return false
        }
        isParentalUnlocked = true
        return true
    }

    func lockParentalControls() {
        isParentalUnlocked = false
    }

    func selectTheme(_ theme: AppTheme) {
        selectedTheme = theme
    }

    func selectPlaybackEnginePreference(_ preference: PlaybackEnginePreference) {
        playbackEnginePreference = preference
    }

    func setCategoryProtection(_ category: String, isProtected: Bool) {
        if isProtected {
            protectedCategories.insert(category)
        } else {
            protectedCategories.remove(category)
        }
    }

    func sourceName(for channel: Channel) -> String {
        sources.first(where: { $0.id == channel.sourceId })?.name ?? "Unknown source"
    }

    func providerHealthReport(for source: MediaSource) -> ProviderHealthReport? {
        providerHealthReports[source.id]
    }

    func isCheckingProviderHealth(_ source: MediaSource) -> Bool {
        providerHealthChecksInProgress.contains(source.id)
    }

    func checkProviderHealth(source: MediaSource) async {
        guard source.kind == .xtream,
              let serverURL = MediaURLValidator.httpURL(from: source.location) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        guard !providerHealthChecksInProgress.contains(source.id) else {
            return
        }

        do {
            guard let credentials = try providerCredentials(for: source) else {
                throw AppError.missingCredentials
            }

            providerHealthChecksInProgress.insert(source.id)
            defer {
                providerHealthChecksInProgress.remove(source.id)
            }

            let client = XtreamClient(
                serverURL: serverURL,
                username: credentials.username,
                password: credentials.password
            )
            providerHealthReports[source.id] = await client.checkHealth(sourceId: source.id)
            persistLibrary()
        } catch {
            present(error)
        }
    }

    func currentProgram(for channel: Channel) -> EPGProgram? {
        guard let tvgId = channel.tvgId else { return nil }
        // O(1) lookup via pre-built index instead of O(n) scan
        return epgIndex[tvgId]
    }

    func nextProgram(for channel: Channel) -> EPGProgram? {
        guard let tvgId = channel.tvgId else { return nil }
        let now = Date()
        // Filter only programs for this channel, then find the soonest upcoming one.
        // We still scan here but it's only called in detail views, not in list rows.
        return epgPrograms
            .lazy
            .filter { $0.channelId == tvgId && $0.startAt > now }
            .min(by: { $0.startAt < $1.startAt })
    }

    /// Rebuilds the O(1) EPG index. Called automatically when `epgPrograms` changes.
    private func rebuildEPGIndex() {
        let now = Date()
        var index: [String: EPGProgram] = [:]
        index.reserveCapacity(epgPrograms.count / 4)
        for program in epgPrograms where program.startAt <= now && program.endAt > now {
            // Keep the first match per channel (programs are typically ordered chronologically)
            if index[program.channelId] == nil {
                index[program.channelId] = program
            }
        }
        epgIndex = index
    }

    private func parsePlaylist(_ playlist: String) async -> [ParsedChannel] {
        await Task.detached(priority: .userInitiated) {
            M3UParser.parse(playlist)
        }.value
    }

    private func saveImport(source: MediaSource, parsed: [ParsedChannel]) async throws {
        guard !parsed.isEmpty else {
            throw AppError.emptyPlaylist
        }

        // Map parsed channels to Channel objects. saveChannels will apply favorite
        // preservation via favoriteMap() — no need to do it twice here.
        let importedChannels = parsed.map {
            Channel(
                sourceId: source.id,
                name: $0.name,
                streamURL: $0.streamURL,
                category: $0.category,
                logoURL: $0.logoURL,
                tvgId: $0.tvgId
            )
        }

        try await saveChannels(source: source, importedChannels: importedChannels)
    }

    private func saveChannels(source: MediaSource, importedChannels: [Channel]) async throws {
        guard !importedChannels.isEmpty else {
            throw AppError.emptyPlaylist
        }

        // Rebuild only the affected source while leaving other imported libraries untouched.
        let existingFavorites = favoriteMap()
        let mergedChannels = uniqueChannels(importedChannels).map { channel in
            var updated = channel
            updated.isFavorite = existingFavorites[channel.streamURL] ?? channel.isFavorite
            return updated
        }

        sources.removeAll { $0.id == source.id }
        sources.append(source)
        sources.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Await so that self.library is fully updated before we snapshot it for persistence.
        await applyLibrary(library.replacingSource(source.id, with: mergedChannels))
        await persistLibraryAsync()
    }

    private func saveProviderImport(source: MediaSource, importResult: ProviderImportResult) async throws {
        let preservedImport = importResultPreservingCachedSections(importResult, sourceId: source.id)
        guard preservedImport.hasContent else {
            throw AppError.emptyPlaylist
        }

        // Provider refreshes can return partial data when one Xtream endpoint times out.
        // Preserve cached sections instead of clearing working catalog data.
        let existingFavorites = favoriteMap()
        var mergedImport = preservedImport
        mergedImport.liveChannels = uniqueLiveChannels(mergedImport.liveChannels).map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }
        mergedImport.movies = uniqueMovies(mergedImport.movies).map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }
        mergedImport.seriesEpisodes = uniqueSeriesEpisodes(mergedImport.seriesEpisodes).map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }

        sources.removeAll { $0.id == source.id }
        sources.append(source)
        sources.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Await so that self.library is fully updated before we snapshot it for persistence.
        await applyLibrary(library.replacingSource(source.id, with: mergedImport))
        await persistLibraryAsync()
    }

    private func mergeSeriesEpisodes(_ episodes: [SeriesEpisode], sourceId: UUID) async throws {
        let existingFavorites = favoriteMap()
        let incomingURLs = Set(episodes.map(\.streamURL))
        var updatedLibrary = library
        updatedLibrary.seriesEpisodes.removeAll { episode in
            episode.sourceId == sourceId && incomingURLs.contains(episode.streamURL)
        }
        updatedLibrary.seriesEpisodes.append(contentsOf: uniqueSeriesEpisodes(episodes).map { episode in
            var updated = episode
            updated.isFavorite = existingFavorites[episode.streamURL] ?? episode.isFavorite
            return updated
        })

        await applyLibrary(updatedLibrary)
        await persistLibraryAsync()
    }

    private func importResultPreservingCachedSections(_ importResult: ProviderImportResult, sourceId: UUID) -> ProviderImportResult {
        var result = importResult
        let cached = providerImportSnapshot(for: sourceId, account: importResult.account, categories: importResult.categories)

        if result.liveChannels.isEmpty {
            result.liveChannels = cached.liveChannels
        }
        if result.movies.isEmpty {
            result.movies = cached.movies
        }
        if result.seriesItems.isEmpty {
            result.seriesItems = cached.seriesItems
        }
        if result.seriesEpisodes.isEmpty {
            result.seriesEpisodes = cached.seriesEpisodes
        }

        return result
    }

    private func providerImportSnapshot(
        for sourceId: UUID,
        account: ProviderAccountInfo?,
        categories: [ProviderCategory]
    ) -> ProviderImportResult {
        ProviderImportResult(
            account: account,
            categories: categories,
            liveChannels: library.liveChannels.filter { $0.sourceId == sourceId },
            movies: library.movies.filter { $0.sourceId == sourceId },
            seriesItems: library.seriesItems.filter { $0.sourceId == sourceId },
            seriesEpisodes: library.seriesEpisodes.filter { $0.sourceId == sourceId }
        )
    }

    private func seriesItemsFromEpisodes() -> [SeriesItem] {
        let groups = Dictionary(grouping: library.seriesEpisodes) { episode in
            "\(episode.sourceId.uuidString)|\(episode.providerSeriesId.map(String.init) ?? episode.seriesTitle ?? episode.category)"
        }

        return groups.compactMap { _, episodes in
            guard let first = episodes.first else {
                return nil
            }
            return SeriesItem(
                sourceId: first.sourceId,
                title: first.seriesTitle?.isEmpty == false ? first.seriesTitle! : first.category,
                category: first.category,
                posterURL: first.posterURL,
                providerSeriesId: first.providerSeriesId,
                episodeCount: episodes.count,
                isFavorite: episodes.contains { $0.isFavorite }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func episodeSort(lhs: SeriesEpisode, rhs: SeriesEpisode) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber {
            return (lhs.seasonNumber ?? 0) < (rhs.seasonNumber ?? 0)
        }
        if lhs.episodeNumber != rhs.episodeNumber {
            return (lhs.episodeNumber ?? 0) < (rhs.episodeNumber ?? 0)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func scheduleProviderEnrichment(source: MediaSource, credentials: ProviderCredentials) {
        providerEnrichmentTasks[source.id]?.cancel()
        providerEnrichmentTasks[source.id] = Task { @MainActor in
            defer {
                providerEnrichmentTasks[source.id] = nil
            }

            do {
                // Give the fast catalog import time to settle before starting heavier full enrichment.
                try await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled,
                      let serverURL = MediaURLValidator.httpURL(from: source.location) else {
                    return
                }

                let client = XtreamClient(
                    serverURL: serverURL,
                    username: credentials.username,
                    password: credentials.password
                )
                let importResult = try await client.fetchProviderLibrary(sourceId: source.id, mode: .full)
                guard !Task.isCancelled, importResult.hasContent else {
                    return
                }

                var enriched = source
                enriched.lastRefreshAt = Date()
                try await saveProviderImport(source: enriched, importResult: importResult)
            } catch is CancellationError {
                return
            } catch {
                // Background enrichment must never block the usable fast catalog.
                return
            }
        }
    }

    private func refreshXtream(source: MediaSource) async {
        guard let serverURL = MediaURLValidator.httpURL(from: source.location) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        beginLoading("Refreshing provider...")
        defer { endLoading() }

        do {
            guard let credentials = try providerCredentials(for: source) else {
                throw AppError.missingCredentials
            }

            var refreshed = source
            refreshed.lastRefreshAt = Date()
            let client = XtreamClient(
                serverURL: serverURL,
                username: credentials.username,
                password: credentials.password
            )
            loadingMessage = "Loading provider catalog..."
            let importResult = try await client.fetchProviderLibrary(sourceId: source.id, mode: .fast)
            loadingMessage = "Indexing provider library..."
            try await saveProviderImport(source: refreshed, importResult: importResult)
            scheduleProviderEnrichment(source: refreshed, credentials: credentials)
        } catch {
            present(error)
        }
    }

    private func remoteText(from url: URL, context: String) async throws -> String {
        do {
            let request = XtreamClient.mediaRequest(url: url, timeout: 240)
            let result: (Data, URLResponse)
            if context.localizedCaseInsensitiveContains("playlist") {
                result = try await XtreamClient.downloadData(for: request, context: context)
            } else {
                result = try await XtreamClient.data(for: request, context: context)
            }
            let (data, response) = result
            try validateHTTPResponse(response, context: context)
            return try text(from: data, context: context)
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw AppError.networkUnavailable(error.localizedDescription)
        } catch {
            throw AppError.importFailed(error.localizedDescription)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, context: String) throws {
        guard let response = response as? HTTPURLResponse else {
            throw AppError.invalidServerResponse
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AppError.httpStatus(response.statusCode, context)
        }
    }

    private func text(from data: Data, context: String) throws -> String {
        // Most playlists are UTF-8, but older panels often export ISO-8859-1 text.
        guard let value = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AppError.importFailed("\(context) could not be read as text.")
        }
        return value
    }

    private func present(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    private func beginLoading(_ message: String) {
        loadingMessage = message
        isLoading = true
    }

    private func endLoading() {
        isLoading = false
        loadingMessage = "Loading..."
    }

    private func cleanName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func existingXtreamSource(for serverURL: URL) -> MediaSource? {
        let target = normalizedProviderLocation(serverURL)
        return sources.first { source in
            guard source.kind == .xtream,
                  let sourceURL = MediaURLValidator.httpURL(from: source.location) else {
                return false
            }
            return normalizedProviderLocation(sourceURL) == target
        }
    }

    private func normalizedProviderLocation(_ url: URL) -> String {
        let baseURL: URL
        if url.lastPathComponent.localizedCaseInsensitiveCompare("player_api.php") == .orderedSame
            || url.lastPathComponent.localizedCaseInsensitiveCompare("get.php") == .orderedSame {
            baseURL = url.deletingLastPathComponent()
        } else {
            baseURL = url
        }

        guard let scheme = baseURL.scheme?.lowercased(),
              let host = baseURL.host?.lowercased() else {
            return baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let port = baseURL.port.map { ":\($0)" } ?? ""
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(scheme)://\(host)\(port)\(path.isEmpty ? "" : "/\(path)")"
    }

    private func setLibrary(_ newLibrary: MediaLibrary) {
        library = newLibrary
        libraryIndex = MediaLibraryIndex(library: newLibrary)
    }

    private func applyLibrary(_ newLibrary: MediaLibrary) async {
        let newIndex = await Task.detached(priority: .userInitiated) {
            MediaLibraryIndex(library: newLibrary)
        }.value
        // Publish a single objectWillChange notification before updating both properties,
        // so any SwiftUI view that re-renders sees consistent library + libraryIndex together.
        objectWillChange.send()
        library = newLibrary
        libraryIndex = newIndex
    }

    private func favoriteMap() -> [String: Bool] {
        var result: [String: Bool] = [:]
        for item in library.liveChannels where item.isFavorite {
            result[item.streamURL] = true
        }
        for item in library.movies where item.isFavorite {
            result[item.streamURL] = true
        }
        for item in library.seriesEpisodes where item.isFavorite {
            result[item.streamURL] = true
        }
        return result
    }

    private func uniqueChannels(_ channels: [Channel]) -> [Channel] {
        var seen = Set<String>()
        return channels.filter { channel in
            seen.insert(channel.streamURL).inserted
        }
    }

    private func uniqueLiveChannels(_ channels: [LiveChannel]) -> [LiveChannel] {
        var seen = Set<String>()
        return channels.filter { channel in
            seen.insert(channel.streamURL).inserted
        }
    }

    private func uniqueMovies(_ movies: [MovieItem]) -> [MovieItem] {
        var seen = Set<String>()
        return movies.filter { movie in
            seen.insert(movie.streamURL).inserted
        }
    }

    private func uniqueSeriesEpisodes(_ episodes: [SeriesEpisode]) -> [SeriesEpisode] {
        var seen = Set<String>()
        return episodes.filter { episode in
            seen.insert(episode.streamURL).inserted
        }
    }

    private func parentalService() -> ParentalControlService {
        ParentalControlService(
            pin: parentalPIN,
            protectedCategories: protectedCategories,
            isUnlocked: isParentalUnlocked
        )
    }

    private func persistParentalPIN() {
        do {
            if parentalPIN.isEmpty {
                KeychainStore.deleteParentalPIN()
            } else {
                try KeychainStore.saveParentalPIN(parentalPIN)
            }
            defaults.removeObject(forKey: Keys.parentalPIN)
        } catch {
            alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
        }
    }

    private func load() async {
        beginLoading("Loading saved library...")
        defer { endLoading() }

        let store = libraryStore
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) { () throws -> LibrarySnapshot? in
                try store.load()
            }.value

            guard let snapshot else {
                migrateLegacyLibraryFromUserDefaults()
                migrateLegacyProviderCredentials()
                return
            }

            sources = snapshot.sources
            let repairedLibrary = snapshot.library.repairingXtreamPlaybackURLs()
            await applyLibrary(repairedLibrary)
            epgPrograms = snapshot.epgPrograms
            epgGuideSource = snapshot.epgGuideSource
            providerHealthReports = snapshot.providerHealthReports
            if repairedLibrary != snapshot.library {
                persistLibrary()
            }
        } catch {
            alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
            migrateLegacyLibraryFromUserDefaults()
        }
        migrateLegacyProviderCredentials()
    }

    /// Persists the library on a background task (non-blocking). Any in-flight save is cancelled first.
    private func persistLibrary() {
        let snapshot = LibrarySnapshot(
            sources: sources,
            library: library,
            epgPrograms: epgPrograms,
            epgGuideSource: epgGuideSource,
            providerHealthReports: providerHealthReports
        )
        let store = libraryStore

        pendingPersistTask?.cancel()
        pendingPersistTask = Task {
            do {
                try await Task.detached(priority: .utility) {
                    try store.save(snapshot)
                }.value
            } catch is CancellationError {
                return
            } catch {
                alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
            }
        }
    }

    /// Awaitable variant used after async library mutations to ensure the snapshot is captured
    /// from the fully-updated state before returning to callers.
    private func persistLibraryAsync() async {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil

        let snapshot = LibrarySnapshot(
            sources: sources,
            library: library,
            epgPrograms: epgPrograms,
            epgGuideSource: epgGuideSource,
            providerHealthReports: providerHealthReports
        )
        let store = libraryStore

        do {
            try await Task.detached(priority: .utility) {
                try store.save(snapshot)
            }.value
        } catch {
            alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
        }
    }

    private func schedulePersistLibrary() {
        let snapshot = LibrarySnapshot(
            sources: sources,
            library: library,
            epgPrograms: epgPrograms,
            epgGuideSource: epgGuideSource,
            providerHealthReports: providerHealthReports
        )
        let store = libraryStore

        pendingPersistTask?.cancel()
        pendingPersistTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                try await Task.detached(priority: .utility) {
                    try store.save(snapshot)
                }.value
            } catch is CancellationError {
                return
            } catch {
                alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        Self.decode(type, key: key, defaults: defaults)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func providerCredentials(for source: MediaSource) throws -> ProviderCredentials? {
        if let credentials = try KeychainStore.credentials(for: source.id) {
            return credentials
        }

        guard let username = source.username, let password = source.password else {
            return nil
        }

        let credentials = ProviderCredentials(username: username, password: password)
        try KeychainStore.save(credentials, for: source.id)
        return credentials
    }

    private func migrateLegacyProviderCredentials() {
        var didMigrate = false

        for index in sources.indices where sources[index].kind == .xtream {
            guard let username = sources[index].username,
                  let password = sources[index].password else {
                continue
            }

            do {
                try KeychainStore.save(
                    ProviderCredentials(username: username, password: password),
                    for: sources[index].id
                )
            } catch {
                alertMessage = error.localizedDescription
                continue
            }
            sources[index].username = nil
            sources[index].password = nil
            didMigrate = true
        }

        if didMigrate {
            persistLibrary()
        }
    }

    private func migrateLegacyLibraryFromUserDefaults() {
        sources = decode([MediaSource].self, key: Keys.sources) ?? []
        let legacyChannels = decode([Channel].self, key: Keys.channels) ?? []
        setLibrary(MediaLibrary.from(channels: legacyChannels).repairingXtreamPlaybackURLs())
        epgPrograms = decode([EPGProgram].self, key: Keys.epgPrograms) ?? []
        epgGuideSource = decode(EPGGuideSource.self, key: Keys.epgGuideSource)

        if !sources.isEmpty || library.count > 0 || !epgPrograms.isEmpty || epgGuideSource != nil {
            persistLibrary()
            removeLegacyLibraryDefaults()
        }
    }

    private func removeLegacyLibraryDefaults() {
        defaults.removeObject(forKey: Keys.sources)
        defaults.removeObject(forKey: Keys.channels)
        defaults.removeObject(forKey: Keys.epgPrograms)
        defaults.removeObject(forKey: Keys.epgGuideSource)
    }
}

private enum Keys {
    static let hasAcceptedTerms = "hasAcceptedTerms"
    static let parentalPIN = "parentalPIN"
    static let protectedCategories = "protectedCategories"
    static let selectedTheme = "selectedTheme"
    static let playbackEnginePreference = "playbackEnginePreference"
    static let sources = "sources"
    static let channels = "channels"
    static let epgPrograms = "epgPrograms"
    static let epgGuideSource = "epgGuideSource"
}
