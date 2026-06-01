import XCTest

final class MediaURLValidatorTests: XCTestCase {
    func testAddsHTTPSWhenSchemeIsMissing() {
        let url = MediaURLValidator.httpURL(from: "example.com:8080")

        XCTAssertEqual(url?.absoluteString, "https://example.com:8080")
    }

    func testRejectsUnsupportedSchemes() {
        XCTAssertNil(MediaURLValidator.httpURL(from: "ftp://example.com/list.m3u"))
    }
}
