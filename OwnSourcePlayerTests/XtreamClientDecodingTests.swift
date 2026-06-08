import Foundation
import XCTest

final class XtreamClientDecodingTests: XCTestCase {
    func testXtreamStreamDecodesSnakeCaseProviderFields() throws {
        let json = """
        {
          "stream_id": 42,
          "name": "Sample Movie",
          "stream_icon": "https://example.com/poster.png",
          "category_id": "7",
          "category_name": "Movies",
          "epg_channel_id": "sample.movie",
          "container_extension": "mp4",
          "tv_archive": "1",
          "tv_archive_duration": "7",
          "release_year": "2026"
        }
        """

        let stream = try JSONDecoder().decode(XtreamStream.self, from: Data(json.utf8))

        XCTAssertEqual(stream.streamId, 42)
        XCTAssertEqual(stream.name, "Sample Movie")
        XCTAssertEqual(stream.streamIcon, "https://example.com/poster.png")
        XCTAssertEqual(stream.categoryName, "Movies")
        XCTAssertEqual(stream.containerExtension, "mp4")
        XCTAssertTrue(stream.hasCatchUp)
        XCTAssertEqual(stream.catchUpDays, 7)
        XCTAssertEqual(stream.releaseYear, "2026")
    }

    func testProviderAccountDecodesStatusAndConnectionInfo() throws {
        let json = """
        {
          "user_info": {
            "username": "demo",
            "status": "Active",
            "exp_date": "1798675200",
            "active_cons": "1",
            "max_connections": "3"
          }
        }
        """

        let response = try JSONDecoder().decode(XtreamAccountResponse.self, from: Data(json.utf8))
        let account = try XCTUnwrap(response.userInfo?.accountInfo)

        XCTAssertEqual(account.username, "demo")
        XCTAssertTrue(account.isActive)
        XCTAssertEqual(account.activeConnections, 1)
        XCTAssertEqual(account.maxConnections, 3)
    }

    func testSeriesInfoDecodesStringEpisodeIdentifiers() throws {
        let json = """
        {
          "episodes": {
            "1": [
              {
                "id": "501",
                "episode_num": "2",
                "title": "Second Episode",
                "container_extension": "mp4",
                "season": "1",
                "info": {
                  "movie_image": "https://example.com/episode.png"
                }
              }
            ]
          }
        }
        """

        let info = try JSONDecoder().decode(XtreamSeriesInfo.self, from: Data(json.utf8))
        let episode = try XCTUnwrap(info.episodes["1"]?.first)

        XCTAssertEqual(episode.id, 501)
        XCTAssertEqual(episode.episodeNumber, 2)
        XCTAssertEqual(episode.season, 1)
        XCTAssertEqual(episode.info?.movieImage, "https://example.com/episode.png")
    }

    func testLiveStreamsDecodeFromWrappedProviderResponse() throws {
        let json = """
        {
          "available_channels": [
            {
              "stream_id": "101",
              "name": "News",
              "stream_icon": 0,
              "category_id": 12,
              "epg_channel_id": 555,
              "tv_archive": "1",
              "tv_archive_duration": 3
            }
          ]
        }
        """

        let streams = try XtreamClient.decodeProviderArray(XtreamStream.self, from: Data(json.utf8))
        let stream = try XCTUnwrap(streams.first)

        XCTAssertEqual(stream.streamId, 101)
        XCTAssertEqual(stream.name, "News")
        XCTAssertEqual(stream.streamIcon, "0")
        XCTAssertEqual(stream.categoryId, "12")
        XCTAssertEqual(stream.epgChannelId, "555")
        XCTAssertTrue(stream.hasCatchUp)
        XCTAssertEqual(stream.catchUpDays, 3)
    }

    func testLiveStreamsDecodeFromDictionaryProviderResponse() throws {
        let json = """
        {
          "101": {
            "stream_id": 101,
            "name": "News"
          },
          "102": {
            "stream_id": 102,
            "name": "Sports"
          }
        }
        """

        let streams = try XtreamClient.decodeProviderArray(XtreamStream.self, from: Data(json.utf8))

        XCTAssertEqual(streams.map(\.streamId), [101, 102])
        XCTAssertEqual(streams.map(\.name), ["News", "Sports"])
    }

    func testLiveStreamsDecodeFromMixedDictionaryProviderResponse() throws {
        let json = """
        {
          "server_info": {
            "url": "example.com"
          },
          "101": {
            "stream_id": 101,
            "name": "News"
          }
        }
        """

        let streams = try XtreamClient.decodeProviderArray(XtreamStream.self, from: Data(json.utf8))

        XCTAssertEqual(streams.map(\.streamId), [101])
        XCTAssertEqual(streams.map(\.name), ["News"])
    }

    func testCategoryDecodesNumericId() throws {
        let json = """
        {
          "category_id": 12,
          "category_name": "Live"
        }
        """

        let category = try JSONDecoder().decode(XtreamCategory.self, from: Data(json.utf8))

        XCTAssertEqual(category.categoryId, "12")
        XCTAssertEqual(category.categoryName, "Live")
    }
}
