import SwiftUI

enum ContentMode: Equatable {
    case live
    case videos

    var title: String {
        switch self {
        case .live:
            return "Live"
        case .videos:
            return "Videos"
        }
    }

    var emptyTitle: String {
        switch self {
        case .live:
            return "No Channels"
        case .videos:
            return "No Videos"
        }
    }

    var emptyDescription: String {
        switch self {
        case .live:
            return "Add a legal playlist source to browse channels."
        case .videos:
            return "On-demand items from your playlists will appear here."
        }
    }
}

struct ChannelListView: View {
    @EnvironmentObject private var store: AppStore
    var contentMode: ContentMode = .live
    @Binding var selectedChannel: Channel?
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private var modeItems: [Channel] {
        switch contentMode {
        case .live:
            return store.channels.filter { !$0.isOnDemand && store.canShow($0) }
        case .videos:
            return store.channels.filter { $0.isOnDemand && store.canShow($0) }
        }
    }

    private var categories: [String] {
        let values = Set(modeItems.map(\.category))
        return ["All", "Favorites"] + values.sorted()
    }

    private var filteredChannels: [Channel] {
        modeItems
            .filter { channel in
                selectedCategory == "All"
                || (selectedCategory == "Favorites" && channel.isFavorite)
                || channel.category == selectedCategory
            }
            .filter { channel in
                searchText.isEmpty
                || channel.name.localizedCaseInsensitiveContains(searchText)
                || channel.category.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if modeItems.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            title: contentMode.emptyTitle,
                            systemImage: contentMode == .live ? "play.tv" : "film",
                            message: contentMode.emptyDescription
                        )

                        if store.sources.isEmpty {
                            Button {
                                store.loadDemoLibrary()
                            } label: {
                                Label("Load Demo Library", systemImage: "play.rectangle.on.rectangle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            BrowserHeader(
                                title: contentMode.title,
                                count: filteredChannels.count,
                                total: modeItems.count,
                                systemImage: contentMode == .live ? "play.tv.fill" : "film.fill"
                            )

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(categories, id: \.self) { category in
                                        CategoryChip(
                                            title: category,
                                            isSelected: selectedCategory == category
                                        ) {
                                            selectedCategory = category
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                            LazyVStack(spacing: 10) {
                                ForEach(filteredChannels) { channel in
                                    Button {
                                        selectedChannel = channel
                                    } label: {
                                        ChannelBrowserRow(channel: channel) {
                                            store.toggleFavorite(channel)
                                        }
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
            .navigationTitle(contentMode.title)
            .searchable(text: $searchText, prompt: contentMode == .live ? "Search channels" : "Search videos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(filteredChannels.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BrowserHeader: View {
    var title: String
    var count: Int
    var total: Int
    var systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.0, green: 0.50, blue: 0.62), Color(red: 0.0, green: 0.75, blue: 0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text("\(count) shown from \(total) items")
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

private struct CategoryChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ChannelBrowserRow: View {
    @EnvironmentObject private var store: AppStore
    var channel: Channel
    var favoriteAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ChannelArtwork(channel: channel, size: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)

                Label(channel.category, systemImage: channel.isOnDemand ? "film" : "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let current = store.currentProgram(for: channel) {
                    Text(current.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: favoriteAction) {
                Image(systemName: channel.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(channel.isFavorite ? .yellow : .secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
