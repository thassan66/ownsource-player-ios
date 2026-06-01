# OwnSource Player

Native iOS media playlist player for user-provided legal live streams and on-demand content.

This app intentionally ships with no channels, playlists, providers, or copyrighted media. Users add their own legal M3U source URLs or local playlist files.

## Current MVP

- SwiftUI iOS app shell
- First-launch legal/safety onboarding
- Add M3U URL source
- Import local M3U file
- Add user-provided provider login
- Validate provider account status
- Import provider live categories, movie categories, series categories, movies, series episodes, and catch-up metadata where available
- Parse basic M3U playlists
- Store sources and channels locally
- Store large library data in an Application Support JSON snapshot
- Split imported items into live, movie, and series episode buckets internally
- Browse channels by source/category
- Browse movies in a dedicated Movies screen
- Browse series groups, seasons, and episodes in a dedicated Series screen
- Search channels
- Favorite channels
- Basic parental PIN and protected categories
- Free appearance themes
- Current/next guide display when channel IDs match EPG data
- Play streams with `AVPlayer`
- Playback buffering, failure observer, and retry UI
- Store provider credentials in Keychain
- Clear local cache/settings

## Current Status

The app is a working iOS foundation, not a complete App Store-ready product. It builds in Xcode and covers the basic source import, browsing, playback, EPG, favorites, and parental-control flows.

Remaining completion work:

- Proper app icon and launch screen branding
- Privacy Policy and Terms screens
- Unit tests for M3U, XMLTV, and provider parsing
- Better provider support: categories, series, episodes, catch-up, and EPG mapping
- Proper VOD and series data model instead of detecting on-demand-looking channels
- Large playlist performance work, including indexing and incremental refresh
- App Store metadata and screenshot-safe demo content
- TestFlight testing on real devices
- Optional Kotlin Multiplatform shared core extraction after the native iOS flow stabilizes

See [Product Roadmap](docs/product-roadmap.md) for the business model, App Store risk controls, and phased feature plan.

## Public Product And Legal Pages

The repo includes a GitHub Pages site in `docs/` and a GitHub Actions workflow at `.github/workflows/pages.yml`.

Expected public URLs after GitHub Pages is enabled and deployed:

- Product page: `https://thassan66.github.io/ownsource-player-ios/`
- Privacy Policy URL: `https://thassan66.github.io/ownsource-player-ios/privacy.html`
- Terms of Use URL: `https://thassan66.github.io/ownsource-player-ios/terms.html`
- Support URL: `https://thassan66.github.io/ownsource-player-ios/support.html`
- App Store privacy answers: `https://thassan66.github.io/ownsource-player-ios/app-store-privacy.html`

For App Store Connect, use the privacy policy URL above and the support URL above. The current app build is local-first and does not include analytics, advertising, tracking, app accounts, cloud sync, or a developer-operated backend, so the prepared privacy-answer page recommends "No, we do not collect data from this app" unless those practices change before submission.

See [App Store Submission Pack](docs/app-store-submission.md), [App Store Connect Fields](docs/app-store-connect-fields.md), and [Screenshot Capture Checklist](docs/screenshot-capture-checklist.md) for draft metadata, privacy questionnaire answers, review notes, TestFlight notes, and screenshot rules.

To publish, push `master` to GitHub, then configure the repository Pages source to GitHub Actions if it is not already enabled.

## Recommended Architecture

Keep the UI/player native on each platform:

- iOS: SwiftUI + AVPlayer
- Android: Jetpack Compose + ExoPlayer / Media3

Share the non-UI core later with Kotlin Multiplatform:

- M3U parser
- XMLTV parser
- Xtream-style API client, if included
- Domain models
- Playlist indexing/search rules
- Validation and diagnostics

That gives a native playback experience while avoiding duplicate parser/provider logic.

## Opening The App

Open `OwnSourcePlayer.xcodeproj` on macOS with Xcode.

Minimum target in the project is iOS 16.0 for wider device support.

## Tests

The project includes a shared Xcode scheme and an initial XCTest bundle for parser/provider logic.

On macOS:

```sh
xcodebuild test -project OwnSourcePlayer.xcodeproj -scheme OwnSourcePlayer -destination 'platform=iOS Simulator,name=iPhone 17'
```

## App Store Safety

- Do not bundle streams or provider lists.
- Do not use screenshots containing copyrighted channels, sports, movies, or premium providers.
- Position the app as a personal media playlist player.
- Require users to confirm they have rights to the sources they add.
- Prefer secure HTTPS source and guide URLs. Avoid broad App Transport Security exceptions unless there is a narrow, documented review justification.
