import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedChannel: Channel?

    var body: some View {
        Group {
            if store.hasAcceptedTerms {
                TabView {
                    HomeView(selectedChannel: $selectedChannel)
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }

                    ChannelListView(selectedChannel: $selectedChannel)
                        .tabItem {
                            Label("Live", systemImage: "play.tv")
                        }

                    MoviesView(selectedChannel: $selectedChannel)
                        .tabItem {
                            Label("Movies", systemImage: "film")
                        }

                    SeriesView(selectedChannel: $selectedChannel)
                        .tabItem {
                            Label("Series", systemImage: "rectangle.stack")
                        }

                    SourceEditorView()
                        .tabItem {
                            Label("Sources", systemImage: "folder.badge.plus")
                        }

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                }
            } else {
                OnboardingView()
            }
        }
        .sheet(item: $selectedChannel) { channel in
            PlayerView(channel: channel)
        }
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    ProgressView("Loading playlist...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .alert("OwnSource Player", isPresented: Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var hasConfirmedLegalUse = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 10) {
                    Text("OwnSource Player")
                        .font(.largeTitle.bold())
                    Text("A private media playlist player for live streams and on-demand content from sources you provide.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("No channels or providers are included.", systemImage: "checkmark.shield")
                    Label("Only add sources you have the legal right to use.", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Your playlists stay on this device.", systemImage: "lock")
                }
                .font(.body)

                Toggle("I will only use legal media sources.", isOn: $hasConfirmedLegalUse)
                    .toggleStyle(.switch)
                    .padding(.top)

                Button {
                    store.hasAcceptedTerms = true
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasConfirmedLegalUse)

                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selectedChannel: Channel?

    private var visibleChannels: [Channel] {
        store.channels.filter { store.canShow($0) }
    }

    private var continueWatching: [Channel] {
        store.recentlyWatched
            .filter { store.canShow($0) }
            .filter(\.isOnDemand)
    }

    private var liveNow: [Channel] {
        let liveChannels = store.library.liveChannels
            .map(\.channel)
            .filter { store.canShow($0) }

        let channelsWithGuide = liveChannels.filter { store.currentProgram(for: $0) != nil }
        return channelsWithGuide.isEmpty ? Array(liveChannels.prefix(12)) : channelsWithGuide
    }

    private var recentlyAdded: [Channel] {
        Array(visibleChannels.reversed().prefix(12))
    }

    private var movieChannels: [Channel] {
        store.library.movies
            .map(\.channel)
            .filter { store.canShow($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var seriesChannels: [Channel] {
        store.library.seriesEpisodes
            .map(\.channel)
            .filter { store.canShow($0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var featuredChannel: Channel? {
        continueWatching.first
            ?? liveNow.first
            ?? store.favoriteChannels.first(where: { store.canShow($0) })
            ?? visibleChannels.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HomeHeroCard(featuredChannel: featuredChannel) { channel in
                        selectedChannel = channel
                    }

                    if store.sources.isEmpty {
                        DemoCalloutCard()
                    } else {
                        HomeSummaryGrid(
                            sources: store.sources.count,
                            live: store.library.liveChannels.count,
                            movies: store.library.movies.count,
                            series: store.library.seriesEpisodes.count
                        )

                        if !continueWatching.isEmpty {
                            HomeRailSection(title: "Continue Watching", subtitle: "Pick up where you left off") {
                                ForEach(Array(continueWatching.prefix(10))) { channel in
                                    HomePosterButton(channel: channel, badge: homeResumeLabel(for: channel)) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }

                        if !liveNow.isEmpty {
                            HomeRailSection(title: "Live Now", subtitle: "Channels with current guide data") {
                                ForEach(Array(liveNow.prefix(12))) { channel in
                                    HomePosterButton(channel: channel, badge: store.currentProgram(for: channel)?.title) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }

                        if !store.favoriteChannels.isEmpty {
                            HomeRailSection(title: "Favorites", subtitle: "Your pinned items") {
                                ForEach(Array(store.favoriteChannels.filter { store.canShow($0) }.prefix(12))) { channel in
                                    HomePosterButton(channel: channel, badge: channel.category) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }

                        if !recentlyAdded.isEmpty {
                            HomeRailSection(title: "Recently Added", subtitle: "Newest items in your library") {
                                ForEach(recentlyAdded) { channel in
                                    HomePosterButton(channel: channel, badge: channel.mediaLabel) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }

                        if !movieChannels.isEmpty {
                            HomeRailSection(title: "Movies", subtitle: "\(movieChannels.count) on-demand videos") {
                                ForEach(Array(movieChannels.prefix(12))) { channel in
                                    HomePosterButton(channel: channel, badge: channel.category) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }

                        if !seriesChannels.isEmpty {
                            HomeRailSection(title: "Series", subtitle: "\(seriesChannels.count) episodes") {
                                ForEach(Array(seriesChannels.prefix(12))) { channel in
                                    HomePosterButton(channel: channel, badge: channel.category) {
                                        selectedChannel = channel
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("OwnSource Player")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct EmptyStateView: View {
    var title: String
    var systemImage: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct HomeHeroCard: View {
    @EnvironmentObject private var store: AppStore
    var featuredChannel: Channel?
    var playAction: (Channel) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let featuredChannel {
                ChannelArtwork(channel: featuredChannel, size: 340)
                    .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 300)
                    .scaleEffect(1.15)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.02, green: 0.12, blue: 0.16), Color(red: 0.0, green: 0.50, blue: 0.58)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.42), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("\(store.library.count) items", systemImage: "rectangle.stack.fill")
                    Label("\(store.epgPrograms.count) guide", systemImage: "calendar")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

                VStack(alignment: .leading, spacing: 6) {
                    Text(featuredChannel?.name ?? "OwnSource Player")
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if let featuredChannel {
                        Button {
                            playAction(featuredChannel)
                        } label: {
                            Label(featuredChannel.isOnDemand ? "Resume" : "Watch", systemImage: "play.fill")
                                .frame(minWidth: 112)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    NavigationLink {
                        SourceEditorView()
                    } label: {
                        Label(store.sources.isEmpty ? "Add Source" : "Manage Sources", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .controlSize(.large)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(.white)
    }

    private var heroSubtitle: String {
        if let featuredChannel {
            if let current = store.currentProgram(for: featuredChannel) {
                return "Now playing: \(current.title)"
            }
            return "\(featuredChannel.mediaLabel) - \(featuredChannel.category)"
        }

        return "A private bring-your-own-playlist player for legal live and on-demand media."
    }
}

private struct DemoCalloutCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Preview the app", systemImage: "sparkles")
                .font(.headline)
            Text("Load fictional screenshot-safe channels, videos, favorites, and guide data to see the finished screens.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                store.loadDemoLibrary()
            } label: {
                Label("Load Demo Library", systemImage: "play.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeSummaryGrid: View {
    var sources: Int
    var live: Int
    var movies: Int
    var series: Int

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(title: "Sources", value: "\(sources)", systemImage: "folder.fill", tint: .blue)
            StatTile(title: "Live", value: "\(live)", systemImage: "play.tv.fill", tint: .teal)
            StatTile(title: "Movies", value: "\(movies)", systemImage: "film.fill", tint: .indigo)
            StatTile(title: "Episodes", value: "\(series)", systemImage: "rectangle.stack.fill", tint: .purple)
        }
    }
}

private struct StatTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HomeRailSection<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct HomePosterButton: View {
    var channel: Channel
    var badge: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ChannelArtwork(channel: channel, size: 128)
                    .overlay(alignment: .topTrailing) {
                        if channel.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                                .padding(7)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                                .padding(7)
                        }
                    }

                Text(channel.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(width: 132, alignment: .topLeading)
                    .frame(minHeight: 36, alignment: .topLeading)

                Text(badge?.isEmpty == false ? badge ?? channel.category : channel.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 132, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private func homeResumeLabel(for channel: Channel) -> String {
    guard let seconds = channel.resumePosition, seconds.isFinite, seconds >= 10 else {
        return channel.category
    }

    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    if hours > 0 {
        return "Resume \(hours)h \(minutes)m"
    }
    return "Resume \(minutes)m"
}

private extension Channel {
    var mediaLabel: String {
        switch mediaKind {
        case .live:
            return "Live"
        case .movie:
            return "Movie"
        case .seriesEpisode:
            return "Episode"
        }
    }
}

struct ChannelRow: View {
    @EnvironmentObject private var store: AppStore
    var channel: Channel

    var body: some View {
        HStack(spacing: 14) {
            ChannelArtwork(channel: channel, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(channel.category)
                    Text("-")
                    Text(store.sourceName(for: channel))
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let current = store.currentProgram(for: channel) {
                    Text("Now: \(current.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let next = store.nextProgram(for: channel) {
                    Text("Next: \(next.title)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if channel.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct ChannelArtwork: View {
    var channel: Channel
    var size: CGFloat

    private var iconName: String {
        if channel.mediaKind == .seriesEpisode {
            return "rectangle.stack.fill"
        }
        if channel.isOnDemand {
            return "film.fill"
        }
        return "play.tv.fill"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.02, green: 0.38, blue: 0.48), Color(red: 0.0, green: 0.68, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            AsyncImage(url: channel.logoURL.flatMap(URL.init(string:))) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } placeholder: {
                Image(systemName: iconName)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
