import SwiftUI

struct MoviesView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedChannel: Channel?
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private var movieResult: LibraryQueryResult<MovieItem> {
        store.movies(category: selectedCategory, searchText: searchText)
    }

    private var categories: [String] {
        store.movieCategories()
    }

    private var countLabel: String {
        movieResult.isLimited ? "\(movieResult.items.count)+" : "\(movieResult.items.count)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.library.movies.isEmpty {
                    LibraryEmptyState(
                        title: "No Movies",
                        message: "Movies from your legal sources will appear here.",
                        systemImage: "film"
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            LibraryHeader(
                                title: "Movies",
                                subtitle: "\(countLabel) shown from \(movieResult.totalCount) movies",
                                systemImage: "film.fill"
                            )

                            CategoryScroller(categories: categories, selectedCategory: $selectedCategory)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                                ForEach(movieResult.items) { movie in
                                    NavigationLink {
                                        MovieDetailView(movie: movie, selectedChannel: $selectedChannel)
                                    } label: {
                                        MoviePosterTile(movie: movie)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Movies")
            .searchable(text: $searchText, prompt: "Search movies")
        }
    }
}

struct SeriesView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedChannel: Channel?
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private var episodeResult: LibraryQueryResult<SeriesEpisode> {
        store.seriesEpisodes(category: selectedCategory, searchText: searchText)
    }

    private var seriesGroups: [SeriesGroup] {
        let grouped = Dictionary(grouping: episodeResult.items) { episode in
            episode.seriesTitle?.isEmpty == false ? episode.seriesTitle! : episode.category
        }

        return grouped
            .map { SeriesGroup(title: $0.key, episodes: $0.value.sorted(by: episodeSort)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var categories: [String] {
        store.seriesCategories()
    }

    private var countLabel: String {
        episodeResult.isLimited ? "\(episodeResult.items.count)+" : "\(episodeResult.items.count)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.library.seriesEpisodes.isEmpty {
                    LibraryEmptyState(
                        title: "No Series",
                        message: "Series episodes from your legal sources will appear here.",
                        systemImage: "rectangle.stack"
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            LibraryHeader(
                                title: "Series",
                                subtitle: "\(countLabel) shown from \(episodeResult.totalCount) episodes",
                                systemImage: "rectangle.stack.fill"
                            )

                            CategoryScroller(categories: categories, selectedCategory: $selectedCategory)

                            LazyVStack(spacing: 12) {
                                ForEach(seriesGroups) { group in
                                    NavigationLink {
                                        SeriesDetailView(group: group, selectedChannel: $selectedChannel)
                                    } label: {
                                        SeriesGroupRow(group: group)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Series")
            .searchable(text: $searchText, prompt: "Search series")
        }
    }
}

private struct MovieDetailView: View {
    @EnvironmentObject private var store: AppStore
    var movie: MovieItem
    @Binding var selectedChannel: Channel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ChannelArtwork(channel: movie.channel, size: 170)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title)
                        .font(.largeTitle.bold())
                    Text(movie.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        selectedChannel = movie.channel
                    } label: {
                        Label(movie.resumePositionText == nil ? "Play" : "Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.toggleFavorite(movie.channel)
                    } label: {
                        Image(systemName: movie.isFavorite ? "star.fill" : "star")
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(movie.isFavorite ? "Remove favorite" : "Add favorite")
                }

                DetailFactGrid(items: [
                    ("Source", store.sourceName(for: movie.channel)),
                    ("Category", movie.category),
                    ("Resume", movie.resumePositionText ?? "Not started"),
                    ("Provider ID", movie.providerItemId.map(String.init) ?? "Unknown")
                ])
            }
            .padding(16)
        }
        .navigationTitle("Movie")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}

private struct SeriesDetailView: View {
    var group: SeriesGroup
    @Binding var selectedChannel: Channel?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.title)
                        .font(.title.bold())
                    Text("\(group.episodes.count) episodes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            ForEach(group.seasonNumbers, id: \.self) { season in
                Section(season.map { "Season \($0)" } ?? "Episodes") {
                    ForEach(group.episodes.filter { $0.seasonNumber == season }) { episode in
                        Button {
                            selectedChannel = episode.channel
                        } label: {
                            EpisodeRow(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EpisodeRow: View {
    var episode: SeriesEpisode

    var body: some View {
        HStack(spacing: 12) {
            ChannelArtwork(channel: episode.channel, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(episodeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let resume = episode.resumePositionText {
                    Text("Resume at \(resume)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if episode.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    private var episodeLabel: String {
        var parts: [String] = []
        if let seasonNumber = episode.seasonNumber {
            parts.append("S\(seasonNumber)")
        }
        if let episodeNumber = episode.episodeNumber {
            parts.append("E\(episodeNumber)")
        }
        parts.append(episode.category)
        return parts.joined(separator: " - ")
    }
}

private struct MoviePosterTile: View {
    var movie: MovieItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChannelArtwork(channel: movie.channel, size: 150)
                .frame(maxWidth: .infinity)

            Text(movie.title)
                .font(.headline)
                .lineLimit(2)

            Text(movie.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let resume = movie.resumePositionText {
                Label(resume, systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension MovieItem {
    var subtitle: String {
        var parts = [category]
        if let releaseYear, !releaseYear.isEmpty {
            parts.append(releaseYear)
        }
        return parts.joined(separator: " - ")
    }

    var resumePositionText: String? {
        resumePosition.flatMap(formatResumePosition)
    }
}

private extension SeriesEpisode {
    var resumePositionText: String? {
        resumePosition.flatMap(formatResumePosition)
    }
}

private func formatResumePosition(_ seconds: Double) -> String? {
    guard seconds.isFinite, seconds >= 10 else {
        return nil
    }

    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let remainder = totalSeconds % 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }

    return "\(minutes)m \(remainder)s"
}

private struct SeriesGroupRow: View {
    var group: SeriesGroup

    var body: some View {
        HStack(spacing: 14) {
            ChannelArtwork(channel: group.episodes.first?.channel ?? placeholderChannel, size: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(group.episodes.count) episodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let first = group.episodes.first {
                    Text(first.category)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeholderChannel: Channel {
        Channel(sourceId: UUID(), name: group.title, streamURL: "about:blank", mediaKind: .seriesEpisode)
    }
}

private struct LibraryHeader: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    store.selectedTheme.gradient
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding([.horizontal, .top], 16)
    }
}

private struct CategoryScroller: View {
    @EnvironmentObject private var store: AppStore
    var categories: [String]
    @Binding var selectedCategory: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selectedCategory == category ? store.selectedTheme.accent : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct DetailFactGrid: View {
    var items: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

private struct LibraryEmptyState: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(title: title, systemImage: systemImage, message: message)
            if store.sources.isEmpty {
                Button {
                    store.loadDemoLibrary()
                } label: {
                    Label("Load Demo Library", systemImage: "play.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct SeriesGroup: Identifiable {
    var title: String
    var episodes: [SeriesEpisode]

    var id: String {
        title
    }

    var seasonNumbers: [Int?] {
        let values = Set(episodes.map(\.seasonNumber))
        return values.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (left?, right?):
                return left < right
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                return false
            }
        }
    }
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
