import XCTest

final class M3UParserTests: XCTestCase {
    func testParseReadsMetadataAndStreamURL() {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-id="news.uk" tvg-logo="https://example.com/news.png" group-title="News",Harbour News
        https://example.com/live/news.m3u8
        """

        let channels = M3UParser.parse(playlist)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Harbour News")
        XCTAssertEqual(channels[0].streamURL, "https://example.com/live/news.m3u8")
        XCTAssertEqual(channels[0].category, "News")
        XCTAssertEqual(channels[0].logoURL, "https://example.com/news.png")
        XCTAssertEqual(channels[0].tvgId, "news.uk")
    }

    func testParseIgnoresCommentsAndNonHttpLines() {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title="Radio",Local Radio
        rtmp://example.com/radio
        #EXTINF:-1 group-title="News",Valid News
        http://example.com/news.ts
        """

        let channels = M3UParser.parse(playlist)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Valid News")
    }

    func testParseUsesExtGroupAndNormalizesSchemeLessURL() {
        let playlist = """
        #EXTM3U
        #EXTGRP:Documentaries
        #EXTINF:-1 tvg-name="Ocean Feed",Ocean Feed
        example.com/live/ocean feed.ts
        """

        let channels = M3UParser.parse(playlist)

        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].name, "Ocean Feed")
        XCTAssertEqual(channels[0].category, "Documentaries")
        XCTAssertEqual(channels[0].streamURL, "http://example.com/live/ocean%20feed.ts")
    }
}

