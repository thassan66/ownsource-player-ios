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
    @State private var categorySearchText = ""
    @State private var categorySort = CategorySortOption.name

    private var libraryKind: LibraryBrowserKind {
        contentMode == .live ? .live : .videos
    }

    private var categories: [String] {
        store.categories(for: libraryKind)
    }

    private var categoryItems: [CategoryMenuItem] {
        categories.map { category in
            CategoryMenuItem(
                title: category,
                count: store.categoryCount(for: libraryKind, category: category)
            )
        }
    }

    private var queryResult: LibraryQueryResult<Channel> {
        store.browserChannels(kind: libraryKind, category: selectedCategory, searchText: searchText)
    }

    private var totalItems: Int {
        switch contentMode {
        case .live:
            return store.library.liveChannels.count
        case .videos:
            return store.library.movies.count + store.library.seriesEpisodes.count
        }
    }

    private var countLabel: String {
        queryResult.isLimited ? "\(queryResult.items.count)+" : "\(queryResult.items.count)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if totalItems == 0 {
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
                    AdaptiveCategoryLayout {
                        List {
                            BrowserHeader(
                                title: contentMode.title,
                                count: countLabel,
                                total: queryResult.totalCount,
                                systemImage: contentMode == .live ? "play.tv.fill" : "film.fill"
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))

                            ForEach(queryResult.items) { channel in
                                Button {
                                    selectedChannel = channel
                                } label: {
                                    ChannelBrowserRow(channel: channel) {
                                        store.toggleFavorite(channel)
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        store.toggleFavorite(channel)
                                    } label: {
                                        Label(
                                            channel.isFavorite ? "Unfavorite" : "Favorite",
                                            systemImage: channel.isFavorite ? "star.slash" : "star.fill"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    } menu: { menuWidth in
                        CategorySideMenu(
                            title: "Categories",
                            items: categoryItems,
                            selectedCategory: $selectedCategory,
                            searchText: $categorySearchText,
                            sortOption: $categorySort,
                            width: menuWidth
                        )
                    }
                }
            }
            .navigationTitle(contentMode.title)
            .searchable(text: $searchText, prompt: contentMode == .live ? "Search channels" : "Search videos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum CategorySortOption: String, CaseIterable, Identifiable {
    case name
    case count

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name:
            return "A-Z"
        case .count:
            return "Items"
        }
    }
}

struct CategoryMenuItem: Identifiable, Hashable {
    var title: String
    var count: Int

    var id: String {
        title
    }

    var isPinned: Bool {
        title == "All" || title == "Favorites"
    }
}

struct AdaptiveCategoryLayout<Content: View, Menu: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var menu: (CGFloat) -> Menu

    var body: some View {
        GeometryReader { proxy in
            let menuWidth = categoryMenuWidth(for: proxy.size.width)

            HStack(alignment: .top, spacing: 0) {
                content
                    .frame(width: max(proxy.size.width - menuWidth, 0), height: proxy.size.height)

                menu(menuWidth)
                    .frame(width: menuWidth, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(CinematicBackground().ignoresSafeArea())
        }
    }

    private func categoryMenuWidth(for availableWidth: CGFloat) -> CGFloat {
        if availableWidth < 430 {
            return min(150, availableWidth * 0.38)
        }
        if availableWidth < 700 {
            return min(190, availableWidth * 0.34)
        }
        return min(280, max(230, availableWidth * 0.26))
    }
}

struct CategorySideMenu: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var items: [CategoryMenuItem]
    @Binding var selectedCategory: String
    @Binding var searchText: String
    @Binding var sortOption: CategorySortOption
    var width: CGFloat = 260

    private var compact: Bool {
        width < 190
    }

    private var visibleItems: [CategoryMenuItem] {
        let pinned = items.filter(\.isPinned)
        let regularItems = items.filter { !$0.isPinned }
        let sortedRegulars: [CategoryMenuItem]

        switch sortOption {
        case .name:
            sortedRegulars = regularItems.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .count:
            sortedRegulars = regularItems.sorted {
                if $0.count == $1.count {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
        }

        let allItems = pinned + sortedRegulars
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return allItems
        }

        return allItems.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack {
                Text(compact ? "Cats" : title)
                    .font(.headline)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10))
                    .clipShape(Capsule())
            }

            Picker("Sort categories", selection: $sortOption) {
                ForEach(CategorySortOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(compact ? "Find" : "Find category", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .font(.subheadline)
            .padding(compact ? 8 : 10)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleItems) { item in
                        Button {
                            selectedCategory = item.title
                        } label: {
                            CategorySideMenuRow(
                                item: item,
                                isSelected: selectedCategory == item.title,
                                compact: compact
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(compact ? 10 : 14)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(0.34))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1)
        }
    }
}

private struct CategorySideMenuRow: View {
    @EnvironmentObject private var store: AppStore
    var item: CategoryMenuItem
    var isSelected: Bool
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 0) {
            HStack(spacing: 10) {
                Text(item.title)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                    .lineLimit(compact ? 2 : 1)

                Spacer(minLength: 8)

                if !compact {
                    countPill
                }
            }

            if compact {
                countPill
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? store.selectedTheme.accent : .white.opacity(0.06))
        .foregroundStyle(isSelected ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var countPill: some View {
        Text("\(item.count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? .white.opacity(0.20) : .white.opacity(0.08))
            .clipShape(Capsule())
    }
}

private struct BrowserHeader: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var count: String
    var total: Int
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
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

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
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding([.horizontal, .top], 16)
    }
}

private struct CategoryChip: View {
    @EnvironmentObject private var store: AppStore
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? store.selectedTheme.accent : Color.white.opacity(0.08))
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

    private func formatEPGTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 14) {
            ChannelArtwork(channel: channel, size: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)

                if let current = store.currentProgram(for: channel) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(current.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        let now = Date()
                        let duration = current.endAt.timeIntervalSince(current.startAt)
                        let elapsed = now.timeIntervalSince(current.startAt)
                        let progress = duration > 0 ? max(0, min(1, elapsed / duration)) : 0.0

                        HStack(spacing: 6) {
                            ProgressView(value: progress)
                                .tint(store.selectedTheme.accent)
                                .frame(width: 80)
                            
                            let startStr = formatEPGTime(current.startAt)
                            let endStr = formatEPGTime(current.endAt)
                            Text("\(startStr) - \(endStr)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            let minutesLeft = Int(current.endAt.timeIntervalSince(now) / 60)
                            if minutesLeft > 0 {
                                Text("(\(minutesLeft)m left)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(store.selectedTheme.accent)
                            }
                        }
                    }
                } else {
                    Label(channel.category, systemImage: channel.isOnDemand ? "film" : "dot.radiowaves.left.and.right")
                        .font(.caption)
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
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
