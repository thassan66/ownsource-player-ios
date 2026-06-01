# App Store Submission Pack

Prepared for the current OwnSource Player build. Keep this file in sync with the shipped app behavior.

## App Information

### Name

OwnSource Player

### Subtitle

Private media playlist player

### Promotional Text

Play and organize legal live streams and on-demand media from sources you provide. OwnSource Player includes no channels, providers, playlists, subscriptions, or copyrighted media.

### Description

OwnSource Player is a private media playlist player for iPhone and iPad. It is designed for people who already have legal media sources and want a simple native app to organize and play them.

Add your own M3U playlist URLs, import local M3U files, connect user-provided provider credentials, and import XMLTV guide data where available. Browse live channels, movies, and series episodes, mark favorites, use local parental category controls, and play streams with the native iOS video player.

OwnSource Player does not provide TV channels, playlists, subscriptions, provider recommendations, premium access, sports, movies, or third-party media services. You are responsible for adding only sources that you own or have permission to use.

Current features:

- Add legal M3U playlist URLs
- Import local M3U and M3U8 playlist files
- Add user-provided provider credentials
- Import XMLTV guide data
- Browse live, movie, and series sections
- Search and filter by category
- Save favorites and recently watched items locally
- Use parental category controls
- Store provider passwords and parental PINs in Keychain
- Play streams with AVPlayer, AirPlay, and Picture in Picture support where available
- Preview the app with fictional screenshot-safe demo data

Privacy-first design:

- No app account is required
- No bundled channels or providers
- No developer-operated media backend
- No advertising or tracking in the current build
- Library data stays on your device

### Keywords

m3u,playlist,player,media,video,stream,epg,xmltv,library,airplay,pip,xtream

### Category

Primary: Entertainment

Secondary: Utilities

### Copyright

2026 Gloud Tech Solutions

## Public URLs

- Support URL: `https://thassan66.github.io/ownsource-player-ios/support.html`
- Privacy Policy URL: `https://thassan66.github.io/ownsource-player-ios/privacy.html`
- Terms URL: `https://thassan66.github.io/ownsource-player-ios/terms.html`
- App Store privacy-answer reference: `https://thassan66.github.io/ownsource-player-ios/app-store-privacy.html`

## App Store Connect Privacy Questionnaire

For the current app behavior:

- Do you or your third-party partners collect data from this app? No
- Does this app use tracking? No
- Data linked to the user? No
- Data used for tracking? No

This remains true only while the app has no analytics, crash reporting SDK, ads, backend logging, accounts, cloud sync, support form inside the app, or other third-party SDK that collects data.

If any of those practices are added, update App Store Connect before release.

## Review Notes

OwnSource Player is a media player only. The app includes no channels, playlists, subscriptions, providers, premium access, sports, movies, or copyrighted media.

Users provide their own legal M3U playlist URLs, local M3U files, XMLTV guide URLs, or provider credentials. The app does not sell, recommend, or bundle any third-party media service.

The app includes a demo mode using fictional screenshot-safe library entries so reviewers can inspect browsing, guide, favorites, and playback flows without a real playlist. Demo playback uses a public Apple developer sample stream.

The app does not require an app account and does not use a developer-operated backend in the current build. Sources, imported library data, favorites, recently watched items, parental category settings, and guide data are stored locally. Provider passwords and parental PINs are stored in the device Keychain.

Suggested review path:

1. Launch the app.
2. Accept the legal-use onboarding.
3. Open Sources or Settings.
4. Tap Load Demo Library.
5. Browse Home, Live, Movies, and Series.
6. Open a demo item to test playback.
7. Review Privacy Policy and Terms from Settings.

## Screenshot Plan

Use fictional/demo library data only. Do not use real channels, sports, movies, provider names, copyrighted logos, or recognizable premium media brands.

Recommended screenshots:

1. Home screen with demo rails and no real media brands.
2. Live screen showing fictional categories and channel names.
3. Movies screen showing fictional on-demand entries.
4. Series screen showing fictional series groups.
5. Sources screen showing legal source import options.
6. Settings screen showing privacy, library counts, legal, and parental controls.

Required device families:

- iPhone screenshots
- iPad screenshots

Before capture:

- Clear all local data.
- Load only demo library.
- Confirm all visible names are fictional.
- Confirm no provider URL, username, password, private playlist URL, or real stream source is visible.

## TestFlight Review Notes

Use the same Review Notes above. Keep the language direct:

- App includes no content.
- Users provide their own legal M3U, Xtream-style, and XMLTV sources.
- Demo mode uses fictional content.
- No app account or developer backend is used in the current build.

## Remaining Submission Blockers

1. Confirm Apple Developer Team and signing.
2. Confirm final app icon and launch screen.
3. Confirm support email works before submission.
4. Enable GitHub Pages and verify public legal URLs return HTTP 200.
5. Capture screenshot-safe iPhone and iPad images from demo data.
6. Archive and upload a TestFlight build from Xcode.
