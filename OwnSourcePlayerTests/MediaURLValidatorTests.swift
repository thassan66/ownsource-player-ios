import XCTest

final class MediaURLValidatorTests: XCTestCase {
    func testAddsHTTPSWhenSchemeIsMissing() {
        let url = MediaURLValidator.httpURL(from: "example.com:8080")

        XCTAssertEqual(url?.absoluteString, "https://example.com:8080")
    }

    func testEncodesSpacesInURLPath() {
        let url = MediaURLValidator.httpURL(from: "https://example.com/live/news channel.m3u8")

        XCTAssertEqual(url?.absoluteString, "https://example.com/live/news%20channel.m3u8")
    }

    func testUsesRequestedDefaultScheme() {
        let url = MediaURLValidator.httpURL(from: "example.com/live/news.ts", defaultScheme: "http")

        XCTAssertEqual(url?.absoluteString, "http://example.com/live/news.ts")
    }

    func testRejectsUnsupportedSchemes() {
        XCTAssertNil(MediaURLValidator.httpURL(from: "ftp://example.com/list.m3u"))
    }
}
