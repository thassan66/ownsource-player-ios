# MVP Roadmap

## Milestone 1: Playable iOS Proof Of Concept

Status: implemented as an initial scaffold

- Native SwiftUI shell
- Legal onboarding
- M3U URL import
- Local M3U file import
- Basic M3U parser
- Channel browser
- Search and category filter
- Favorites
- AVPlayer playback
- Local persistence
- User-provided provider login
- Basic parental PIN and protected categories
- XMLTV EPG URL import
- Current/next programme display
- Playback buffering state, failure observer, and retry UI

## Milestone 2: Quality Pass
- Unit tests for M3U parsing: started
- Unit tests for XMLTV parsing: started
- Unit tests for provider response decoding: started
- Shared Xcode scheme for app/test execution: added
- Xcode repo hygiene ignores: added
- `AppStore` helper extraction for demo data, URL validation, and parental gating: started
- Better playlist error reporting
- Handle duplicate channels
- Persist recently watched per channel URL
- Better loading states
- Replace placeholder app icon
- Add launch screen branding
- Add Privacy Policy and Terms screens
- Move large persisted library data out of `UserDefaults`
- Split library into explicit live, movie, and series episode buckets
- Migrate legacy library data from `UserDefaults` into Application Support JSON
- Add large playlist performance pass

## Milestone 3: EPG Quality

- XMLTV import from playlist metadata or manual URL
- Now/next display
- Channel-to-EPG matching
- EPG cache pruning
- Save guide source URL and support guide refresh
- Map provider EPG IDs more reliably
- Show programme details

## Milestone 4: VOD

- VOD item model: started
- Movie and series views: started
- Series, season, and episode models: started
- Provider category mapping
- Catch-up metadata support
- Resume playback
- Watch history
- Dedicated Movies tab: added
- Dedicated Series tab with grouped episodes: added

## Milestone 4a: Provider Completeness

Status: started

- Account/server validation: started
- Live, movie, and series category fetching: started
- Live catch-up metadata mapping: started
- Movie provider item IDs and release years: started
- Series info and episode mapping: started
- Flexible provider decoding for mixed string/number IDs: started
- Dedicated movie and series UI: pending
- Catch-up playback UI: pending

## Milestone 5: App Store Readiness

- Production bundle identifier and signing team
- App icon and launch screen complete
- Privacy Policy and Terms content linked in app
- Screenshot-safe demo sources/content
- App Store metadata, age rating, and privacy nutrition details
- TestFlight testing on real devices
- Fix device-specific playback, import, and layout issues

## Milestone 6: Shared Core Decision

- Extract parser/domain logic into a standalone module
- Decide whether to create Kotlin Multiplatform shared core
- Build Android proof of concept using the same parser fixtures
