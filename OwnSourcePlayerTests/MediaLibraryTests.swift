import Foundation
import XCTest

final class MediaLibraryTests: XCTestCase {
    func testSplitsChannelsByMediaKindAndRebuildsCompatibilityList() {
        let sourceId = UUID()
        let channels = [
            Channel(sourceId: sourceId, name: "News", streamURL: "https://example.com/news.m3u8", mediaKind: .live),
            Channel(sourceId: sourceId, name: "Movie", streamURL: "https://example.com/movie.mp4", mediaKind: .movie),
            Channel(sourceId: sourceId, name: "Episode", streamURL: "https://example.com/episode.mp4", mediaKind: .seriesEpisode)
        ]

        let library = MediaLibrary.from(channels: channels)

        XCTAssertEqual(library.liveChannels.count, 1)
        XCTAssertEqual(library.movies.count, 1)
        XCTAssertEqual(library.seriesEpisodes.count, 1)
        XCTAssertEqual(library.allChannels.count, 3)
    }

    func testReplacingSourceKeepsOtherSources() {
        let firstSourceId = UUID()
        let secondSourceId = UUID()
        let original = MediaLibrary.from(channels: [
            Channel(sourceId: firstSourceId, name: "Old", streamURL: "https://example.com/old.m3u8", mediaKind: .live),
            Channel(sourceId: secondSourceId, name: "Keep", streamURL: "https://example.com/keep.m3u8", mediaKind: .live)
        ])

        let updated = original.replacingSource(firstSourceId, with: [
            Channel(sourceId: firstSourceId, name: "New", streamURL: "https://example.com/new.m3u8", mediaKind: .live)
        ])

        XCTAssertEqual(updated.allChannels.map(\.name).sorted(), ["Keep", "New"])
    }

    func testLiveChannelDecodingDefaultsCatchUpForOlderSnapshots() throws {
        let sourceId = UUID()
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "sourceId": "\(sourceId.uuidString)",
          "name": "News",
          "streamURL": "https://example.com/news.m3u8",
          "category": "News",
          "isFavorite": false
        }
        """

        let channel = try JSONDecoder().decode(LiveChannel.self, from: Data(json.utf8))

        XCTAssertFalse(channel.hasCatchUp)
        XCTAssertNil(channel.catchUpDays)
    }

    func testUpdatingResumePositionPreservesSeriesMetadata() {
        let sourceId = UUID()
        let channel = Channel(sourceId: sourceId, name: "Episode", streamURL: "https://example.com/e1.mp4", mediaKind: .seriesEpisode)
        var episode = SeriesEpisode(channel: channel)
        episode.seriesTitle = "Design Notes"
        episode.providerSeriesId = 10
        let library = MediaLibrary(seriesEpisodes: [episode])

        let updated = library.updatingResumePosition(channelId: channel.id, seconds: 91)

        XCTAssertEqual(updated.seriesEpisodes.first?.resumePosition, 91)
        XCTAssertEqual(updated.seriesEpisodes.first?.seriesTitle, "Design Notes")
        XCTAssertEqual(updated.seriesEpisodes.first?.providerSeriesId, 10)
    }

    func testRepairsXtreamPlaybackURLsThatIncludeAPIEndpoint() {
        let sourceId = UUID()
        let library = MediaLibrary.from(channels: [
            Channel(
                sourceId: sourceId,
                name: "Movie",
                streamURL: "http://example.com:8080/player_api.php/movie/user/pass/99.mp4",
                mediaKind: .movie
            )
        ])

        let repaired = library.repairingXtreamPlaybackURLs()

        XCTAssertEqual(repaired.movies.first?.streamURL, "http://example.com:8080/movie/user/pass/99.mp4")
    }
}
