import Foundation

struct LibrarySnapshot: Codable, Hashable {
    var schemaVersion: Int
    var sources: [MediaSource]
    var library: MediaLibrary
    var epgPrograms: [EPGProgram]
    var epgGuideSource: EPGGuideSource?
    var providerHealthReports: [UUID: ProviderHealthReport]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sources
        case library
        case epgPrograms
        case epgGuideSource
        case providerHealthReports
    }

    init(
        schemaVersion: Int = 2,
        sources: [MediaSource] = [],
        library: MediaLibrary = MediaLibrary(),
        epgPrograms: [EPGProgram] = [],
        epgGuideSource: EPGGuideSource? = nil,
        providerHealthReports: [UUID: ProviderHealthReport] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.sources = sources
        self.library = library
        self.epgPrograms = epgPrograms
        self.epgGuideSource = epgGuideSource
        self.providerHealthReports = providerHealthReports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 2
        sources = try container.decodeIfPresent([MediaSource].self, forKey: .sources) ?? []
        library = try container.decodeIfPresent(MediaLibrary.self, forKey: .library) ?? MediaLibrary()
        epgPrograms = try container.decodeIfPresent([EPGProgram].self, forKey: .epgPrograms) ?? []
        epgGuideSource = try container.decodeIfPresent(EPGGuideSource.self, forKey: .epgGuideSource)
        providerHealthReports = try container.decodeIfPresent([UUID: ProviderHealthReport].self, forKey: .providerHealthReports) ?? [:]
    }
}

struct LibraryPersistenceStore {
    private let fileURL: URL
    private let legacyFileURLs: [URL]

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("OwnSourcePlayer", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("library-v2.json")
        // Read older storage locations after product renames, but save new snapshots under OwnSourcePlayer.
        legacyFileURLs = ["GloudPlayer", "ClearStreamPlayer", "VelaPlayer"].map {
            baseURL
                .appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("library-v2.json")
        }
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        legacyFileURLs = []
    }

    func load() throws -> LibrarySnapshot? {
        let readableFileURL = ([fileURL] + legacyFileURLs).first {
            FileManager.default.fileExists(atPath: $0.path)
        }

        guard let readableFileURL else {
            return nil
        }

        let data = try Data(contentsOf: readableFileURL)
        return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
    }

    func save(_ snapshot: LibrarySnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    func delete() throws {
        for url in [fileURL] + legacyFileURLs where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
