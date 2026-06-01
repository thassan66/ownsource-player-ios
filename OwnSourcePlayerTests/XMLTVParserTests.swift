import XCTest

final class XMLTVParserTests: XCTestCase {
    func testParseReadsProgrammeTitleAndDates() {
        let xml = """
        <tv>
          <programme start="20260531100000 +0100" stop="20260531103000 +0100" channel="news.uk">
            <title lang="en">Morning &amp; Markets</title>
          </programme>
        </tv>
        """

        let programmes = XMLTVParser.parse(xml)

        XCTAssertEqual(programmes.count, 1)
        XCTAssertEqual(programmes[0].channelId, "news.uk")
        XCTAssertEqual(programmes[0].title, "Morning & Markets")
        XCTAssertLessThan(programmes[0].startAt, programmes[0].endAt)
    }
}

