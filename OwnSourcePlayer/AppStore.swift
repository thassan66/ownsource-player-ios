import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sources: [MediaSource] = []
    @Published private(set) var library = MediaLibrary()
    @Published private(set) var libraryIndex = MediaLibraryIndex()
    @Published private(set) var epgPrograms: [EPGProgram] = []
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
    @Published var isLoading = false
    @Published var alertMessage: String?

    private let defaults = UserDefaults.standard
    private let libraryStore = LibraryPersistenceStore()

    init() {
        hasAcceptedTerms = defaults.bool(forKey: Keys.hasAcceptedTerms)
        let keychainPIN = try? KeychainStore.parentalPIN()
        let legacyPIN = defaults.string(forKey: Keys.parentalPIN)
        parentalPIN = keychainPIN ?? legacyPIN ?? ""
        protectedCategories = Set(Self.decode([String].self, key: Keys.protectedCategories, defaults: defaults) ?? [])
        if keychainPIN == nil, legacyPIN?.isEmpty == false {
            persistParentalPIN()
        }
        defaults.removeObject(forKey: Keys.parentalPIN)
        load()
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
        ["All", "Favorites"] + libraryIndex.seriesCategories
    }

    func protectableCategories() -> [String] {
        libraryIndex.allCategories
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

        isLoading = true
        defer { isLoading = false }

        do {
            let playlist = try await remoteText(from: url, context: "Playlist import")
            let source = MediaSource(name: cleanName(name, fallback: url.host ?? "Playlist"), kind: .m3uURL, location: url.absoluteString, lastRefreshAt: Date())
            try saveImport(source: source, playlist: playlist)
        } catch {
            present(error)
        }
    }

    func importLocalFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["m3u", "m3u8", "txt"].contains(ext) else {
            alertMessage = AppError.unsupportedFile.localizedDescription
            return
        }

        do {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let playlist = try text(from: data, context: "Playlist file")

            let source = MediaSource(name: url.deletingPathExtension().lastPathComponent, kind: .m3uFile, location: url.lastPathComponent, lastRefreshAt: Date())
            try saveImport(source: source, playlist: playlist)
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

        isLoading = true
        defer { isLoading = false }

        do {
            let source = MediaSource(
                name: cleanName(name, fallback: serverURL.host ?? "Media Source"),
                kind: .xtream,
                location: serverURL.absoluteString,
                lastRefreshAt: Date()
            )
            let client = XtreamClient(serverURL: serverURL, username: trimmedUsername, password: trimmedPassword)
            let importResult = try await client.fetchProviderLibrary(sourceId: source.id)
            try KeychainStore.save(
                ProviderCredentials(username: trimmedUsername, password: trimmedPassword),
                for: source.id
            )
            try saveProviderImport(source: source, importResult: importResult)
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
        isLoading = true
        defer { isLoading = false }

        do {
            let xml = try await remoteText(from: url, context: "Guide import")
            let programs = XMLTVParser.parse(xml)
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

        isLoading = true
        defer { isLoading = false }

        do {
            let playlist = try await remoteText(from: url, context: "Playlist refresh")
            var refreshed = source
            refreshed.lastRefreshAt = Date()
            try saveImport(source: refreshed, playlist: playlist)
        } catch {
            present(error)
        }
    }

    func deleteSource(_ source: MediaSource) {
        sources.removeAll { $0.id == source.id }
        setLibrary(library.removingSource(source.id))
        KeychainStore.deleteCredentials(for: source.id)
        persistLibrary()
    }

    func toggleFavorite(_ channel: Channel) {
        guard libraryIndex.contains(channel.id) else {
            return
        }

        setLibrary(library.updatingFavorite(channelId: channel.id))
        persistLibrary()
    }

    func markWatched(_ channel: Channel) {
        guard libraryIndex.contains(channel.id) else {
            return
        }

        setLibrary(library.markingWatched(channelId: channel.id))
        persistLibrary()
    }

    func updateResumePosition(for channel: Channel, seconds: Double) {
        guard channel.isOnDemand,
              seconds.isFinite,
              libraryIndex.contains(channel.id) else {
            return
        }

        setLibrary(library.updatingResumePosition(channelId: channel.id, seconds: seconds))
        persistLibrary()
    }

    func clearAllData() {
        sources.forEach { KeychainStore.deleteCredentials(for: $0.id) }
        sources = []
        setLibrary(MediaLibrary())
        epgPrograms = []
        epgGuideSource = nil
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

    func currentProgram(for channel: Channel) -> EPGProgram? {
        guard let tvgId = channel.tvgId else {
            return nil
        }

        let now = Date()
        return epgPrograms.first {
            $0.channelId == tvgId && $0.startAt <= now && $0.endAt > now
        }
    }

    func nextProgram(for channel: Channel) -> EPGProgram? {
        guard let tvgId = channel.tvgId else {
            return nil
        }

        let now = Date()
        return epgPrograms
            .filter { $0.channelId == tvgId && $0.startAt > now }
            .sorted { $0.startAt < $1.startAt }
            .first
    }

    private func saveImport(source: MediaSource, playlist: String) throws {
        let parsed = M3UParser.parse(playlist)
        guard !parsed.isEmpty else {
            throw AppError.emptyPlaylist
        }

        // Preserve user state by matching favorites to stream URLs across refreshes.
        let existingFavorites = favoriteMap()
        let importedChannels = parsed.map {
            Channel(
                sourceId: source.id,
                name: $0.name,
                streamURL: $0.streamURL,
                category: $0.category,
                logoURL: $0.logoURL,
                tvgId: $0.tvgId,
                isFavorite: existingFavorites[$0.streamURL] ?? false
            )
        }

        try saveChannels(source: source, importedChannels: importedChannels)
    }

    private func saveChannels(source: MediaSource, importedChannels: [Channel]) throws {
        guard !importedChannels.isEmpty else {
            throw AppError.emptyPlaylist
        }

        // Rebuild only the affected source while leaving other imported libraries untouched.
        let existingFavorites = favoriteMap()
        let mergedChannels = importedChannels.map { channel in
            var updated = channel
            updated.isFavorite = existingFavorites[channel.streamURL] ?? channel.isFavorite
            return updated
        }

        sources.removeAll { $0.id == source.id }
        sources.append(source)
        sources.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        setLibrary(library.replacingSource(source.id, with: mergedChannels))
        persistLibrary()
    }

    private func saveProviderImport(source: MediaSource, importResult: ProviderImportResult) throws {
        guard importResult.allChannels.isEmpty == false else {
            throw AppError.emptyPlaylist
        }

        // Provider refreshes return new model values, so copy over local-only user flags.
        let existingFavorites = favoriteMap()
        var mergedImport = importResult
        mergedImport.liveChannels = importResult.liveChannels.map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }
        mergedImport.movies = importResult.movies.map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }
        mergedImport.seriesEpisodes = importResult.seriesEpisodes.map { item in
            var updated = item
            updated.isFavorite = existingFavorites[item.streamURL] ?? item.isFavorite
            return updated
        }

        sources.removeAll { $0.id == source.id }
        sources.append(source)
        sources.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        setLibrary(library.replacingSource(source.id, with: mergedImport))
        persistLibrary()
    }

    private func refreshXtream(source: MediaSource) async {
        guard let serverURL = MediaURLValidator.httpURL(from: source.location) else {
            alertMessage = AppError.invalidURL.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

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
            let importResult = try await client.fetchProviderLibrary(sourceId: source.id)
            try saveProviderImport(source: refreshed, importResult: importResult)
        } catch {
            present(error)
        }
    }

    private func remoteText(from url: URL, context: String) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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

    private func cleanName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func setLibrary(_ newLibrary: MediaLibrary) {
        library = newLibrary
        libraryIndex = MediaLibraryIndex(library: newLibrary)
    }

    private func favoriteMap() -> [String: Bool] {
        favoriteChannels.reduce(into: [String: Bool]()) { result, channel in
            result[channel.streamURL] = true
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

    private func load() {
        do {
            guard let snapshot = try libraryStore.load() else {
                migrateLegacyLibraryFromUserDefaults()
                migrateLegacyProviderCredentials()
                return
            }

            sources = snapshot.sources
            setLibrary(snapshot.library)
            epgPrograms = snapshot.epgPrograms
            epgGuideSource = snapshot.epgGuideSource
        } catch {
            alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
            migrateLegacyLibraryFromUserDefaults()
        }
        migrateLegacyProviderCredentials()
    }

    private func persistLibrary() {
        let snapshot = LibrarySnapshot(
            sources: sources,
            library: library,
            epgPrograms: epgPrograms,
            epgGuideSource: epgGuideSource
        )

        do {
            try libraryStore.save(snapshot)
        } catch {
            alertMessage = AppError.storageFailed(error.localizedDescription).localizedDescription
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
        setLibrary(MediaLibrary.from(channels: legacyChannels))
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
    static let sources = "sources"
    static let channels = "channels"
    static let epgPrograms = "epgPrograms"
    static let epgGuideSource = "epgGuideSource"
}
