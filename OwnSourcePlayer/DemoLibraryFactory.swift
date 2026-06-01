import Foundation

struct DemoLibrary {
    var source: MediaSource
    var channels: [Channel]
    var programs: [EPGProgram]
    var guideSource: EPGGuideSource
}

enum DemoLibraryFactory {
    static func make(now: Date = Date()) -> DemoLibrary {
        let demoStreamURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
        let source = MediaSource(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
            name: "OwnSource Demo Library",
            kind: .m3uFile,
            location: "Built-in playable demo data",
            lastRefreshAt: now
        )

        let channels = [
            Channel(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222201") ?? UUID(),
                sourceId: source.id,
                name: "Harbour News",
                streamURL: demoStreamURL,
                category: "News",
                mediaKind: .live,
                logoURL: nil,
                tvgId: "demo.harbour.news",
                isFavorite: true,
                lastWatchedAt: now.addingTimeInterval(-3600)
            ),
            Channel(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222202") ?? UUID(),
                sourceId: source.id,
                name: "City Weather",
                streamURL: demoStreamURL,
                category: "Weather",
                mediaKind: .live,
                logoURL: nil,
                tvgId: "demo.city.weather",
                isFavorite: false
            ),
            Channel(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222203") ?? UUID(),
                sourceId: source.id,
                name: "Studio Fitness",
                streamURL: demoStreamURL,
                category: "Lifestyle",
                mediaKind: .live,
                logoURL: nil,
                tvgId: "demo.studio.fitness",
                isFavorite: true,
                lastWatchedAt: now.addingTimeInterval(-7200)
            ),
            Channel(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222204") ?? UUID(),
                sourceId: source.id,
                name: "Open Kitchen: Spring Menu",
                streamURL: demoStreamURL,
                category: "Movies",
                mediaKind: .movie
            ),
            Channel(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222205") ?? UUID(),
                sourceId: source.id,
                name: "Design Notes S1 E1",
                streamURL: demoStreamURL,
                category: "Series",
                mediaKind: .seriesEpisode,
                isFavorite: true
            )
        ]

        let programs = [
            EPGProgram(
                channelId: "demo.harbour.news",
                title: "Morning Briefing",
                startAt: now.addingTimeInterval(-1800),
                endAt: now.addingTimeInterval(1800)
            ),
            EPGProgram(
                channelId: "demo.harbour.news",
                title: "Local Business Update",
                startAt: now.addingTimeInterval(1800),
                endAt: now.addingTimeInterval(5400)
            ),
            EPGProgram(
                channelId: "demo.city.weather",
                title: "Five Day Forecast",
                startAt: now.addingTimeInterval(-900),
                endAt: now.addingTimeInterval(2700)
            ),
            EPGProgram(
                channelId: "demo.studio.fitness",
                title: "Low Impact Strength",
                startAt: now.addingTimeInterval(-1200),
                endAt: now.addingTimeInterval(2400)
            )
        ]

        let guideSource = EPGGuideSource(
            urlString: "https://example.com/vela-demo/guide.xml",
            importedAt: now,
            lastRefreshAt: now
        )

        return DemoLibrary(source: source, channels: channels, programs: programs, guideSource: guideSource)
    }
}
