import XCTest

final class LibraryPersistenceStoreTests: XCTestCase {
    func testSaveAndLoadSnapshot() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("library-v2.json")
        let store = LibraryPersistenceStore(fileURL: fileURL)

        let source = MediaSource(name: "Test", kind: .m3uURL, location: "https://example.com/list.m3u")
        let channel = Channel(sourceId: source.id, name: "News", streamURL: "https://example.com/news.m3u8")
        let snapshot = LibrarySnapshot(
            sources: [source],
            library: MediaLibrary.from(channels: [channel])
        )

        try store.save(snapshot)
        let loaded = try store.load()

        XCTAssertEqual(loaded?.sources.first?.name, "Test")
        XCTAssertEqual(loaded?.library.allChannels.first?.name, "News")

        try store.delete()
        XCTAssertNil(try store.load())
    }
}

