# OwnSource Player Product Roadmap

OwnSource Player is a legal bring-your-own-playlist media player. The product must never sell, bundle, recommend, or market channels, movies, sports, providers, playlist subscriptions, or premium IPTV access.

## Product Positioning

- User promise: a private player for legal sources the user already has the right to access.
- Business model: monetize app capability, not media content.
- Trust model: no bundled content, no provider directory, no copyrighted screenshots, local-first data storage, clear privacy and terms.
- App Store posture: avoid misleading IPTV marketing and be ready to explain all user-provided content flows.

## Monetization

Use Apple In-App Purchase for paid digital features.

Free tier:
- Add one source.
- Basic live, movie, and series browsing.
- Basic playback.
- Local favorites.
- Demo library.

Pro unlock:
- Unlimited sources.
- Advanced EPG grid and reminders.
- Playlist diagnostics and cleanup tools.
- More themes and layout options.
- Parental profiles and protected category groups.
- Multi-device sync and encrypted backup when backend support exists.
- Background refresh and smart indexing for large libraries.

Subscription tier:
- Cloud backup and sync.
- Cross-device watch history.
- Priority support.
- Provider-agnostic metadata enrichment, only where legally safe.

## Near-Term Build Plan

1. Brand foundation
- Finalize name, icon, launch screen, color system, and screenshot-safe demo content.
- Keep app metadata focused on personal media library management.

2. Netflix-style home
- Add rails for Continue Watching, Favorites, Recently Added, Live Now, Movies, and Series.
- Make the empty state guide users toward legal source import or demo mode.

3. Better playback
- Add scrubber for on-demand content.
- Add Picture in Picture.
- Add AirPlay route controls.
- Add subtitle and audio track selection where AVPlayer exposes options.
- Add playback speed for on-demand content.

4. EPG and channel detail
- Build a real guide grid.
- Add channel detail pages with current/next programme data.
- Improve XMLTV channel matching and diagnostics.

5. Scale and reliability
- Add playlist indexing for large imports.
- Add lazy loading and category indexes.
- Add background refresh with failure summaries.
- Add import diagnostics for invalid URLs, duplicate streams, empty categories, and unsupported formats.

6. Commerce
- Add a StoreKit 2 entitlement layer.
- Gate Pro features with a single local entitlement source.
- Keep paid feature copy clear and separate from any content claims.

## App Store Risk Controls

- Do not include provider names, sports/movie/channel brands, or copyrighted media in screenshots.
- Do not mention free premium channels, IPTV subscriptions, sports, movies, or provider access in marketing.
- Prefer HTTPS source and guide URLs where possible.
- Avoid broad App Transport Security exceptions. If media exceptions remain, prepare a plain justification: the app plays user-provided media URLs from third-party servers the developer does not control.
- Provide support contact, privacy policy URL, and terms URL before TestFlight/App Store submission.

## Company Path

Start as a focused utility under Gloud Tech Solutions:
- Ship a stable iOS MVP.
- Build a small landing page with legal positioning, screenshots from demo data, support email, and privacy/terms.
- Run TestFlight with 20-50 trusted users who use legal playlists.
- Charge only after playback, import, and EPG are reliable.
- Expand to Apple TV first if users ask for living-room use; Android comes after the core parser/provider logic is stable.
