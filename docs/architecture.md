# Architecture Notes

## Native iOS First, Shared Core Later

The safest build path is a native iOS app first, with clear seams for a future shared Kotlin Multiplatform core.

## Why Not Put Everything In Kotlin Multiplatform?

Kotlin Multiplatform is strong for shared business logic, but the best media playback and platform experience still comes from native UI/player layers:

- iOS: SwiftUI, AVPlayer, AirPlay, Picture in Picture
- Android: Jetpack Compose, Media3/ExoPlayer, Android TV support
Trying to share the whole UI/player stack would slow the product down and make platform-specific playback issues harder to solve.

## What Should Be Shared Later

Good KMP candidates:

- M3U parser
- XMLTV EPG parser
- Xtream-style API client, if included
- Domain models
- Playlist validation
- Search indexing rules
- Stream diagnostics
- Category/favorites business rules

Keep native:

- Screens/navigation
- Video player
- PiP/AirPlay/Cast integrations
- File picker
- Keychain/platform secure storage
- App Store and Play Store specific flows

## Current iOS Boundaries

- SwiftUI views own screen state, navigation, and presentation.
- `AppStore` owns app-level state, source import, persistence, favorites, recently watched, EPG lookup, and parental gating.
- `KeychainStore` owns secure provider credential persistence.
- `M3UParser`, `XMLTVParser`, and `XtreamClient` are the current parser/provider core candidates for future extraction.
- `PlayerView` owns AVPlayer setup, buffering state, playback failure observation, and retry UI.
- `MediaURLValidator`, `ParentalControlService`, and `DemoLibraryFactory` are the first extracted support services from `AppStore`.
- `MediaLibrary` now splits imported items into live channels, movies, and series episodes while exposing a compatibility list for the current UI.
- `LibraryPersistenceStore` stores sources, media library, and EPG data in an Application Support JSON snapshot instead of `UserDefaults`.
- `XtreamClient` now fetches provider account info, categories, live streams, movies, series, and series episodes into `ProviderImportResult`.

## Near-Term Architecture Gaps

- `MediaSource` still has legacy optional `username` and `password` fields for migration compatibility. Remove them after a migration window.
- Channels still power the current UI as a compatibility layer. Continue moving screens toward explicit live/movie/series models.
- Movies and Series screens now read from explicit `MediaLibrary` buckets while handing playback to the shared `PlayerView`.
- EPG import is global. Add pruning and provider/source-level mapping.
- Library data is file-backed JSON for the alpha. Move to SQLite/Core Data if large-library write/read performance becomes a bottleneck.
- Large playlist search/filtering currently recomputes from arrays. Add normalized indexes for channel name, category, source, favorite state, and content type.
- Provider support now maps categories, streams, movies, series episodes, catch-up metadata, and EPG IDs into explicit models. The next gap is dedicated UI for movies, series, seasons, and catch-up playback.

## Suggested Future Module Layout

```text
OwnSourcePlayer/
  iosApp/
    SwiftUI app
  androidApp/
    Compose app
  sharedCore/
    Kotlin Multiplatform library
      commonMain/
        parsers/
        models/
        providers/
        diagnostics/
      iosMain/
      androidMain/
```

## App Store Safety Rules

- Do not bundle playlists, channels, provider names, or copyrighted logos.
- Do not market the app as free TV, free sports, premium streaming, or IPTV subscription access.
- Use legal demo streams only in development and screenshots.
- Keep provider integrations generic and user-entered.
- Make source ownership/legal responsibility clear during onboarding.
- Keep App Store metadata, screenshots, and review notes aligned with `docs/app-store-submission.md`.
- Current App Store privacy answers stay valid only while the app has no analytics, crash reporting SDK, ads, backend logging, accounts, cloud sync, or tracking.

## Next Engineering Steps

1. Set the Apple Developer Team and production bundle identifier.
2. Add proper app icon and launch screen branding.
3. Verify GitHub Pages legal URLs return HTTP 200.
4. Expand the test target with fixtures for M3U, XMLTV, and provider responses.
5. Add explicit VOD/series models and views.
6. Expand provider support for categories, series, episodes, catch-up, and EPG mapping.
7. Move playlist/channel persistence from `UserDefaults` to SwiftData or a lightweight database.
8. Add playlist indexing and incremental refresh for large libraries.
9. Prepare screenshot-safe demo screenshots from fictional demo content.
10. Test on real devices through TestFlight.
11. Revisit Kotlin Multiplatform extraction only after the native iOS domain model is stable.
