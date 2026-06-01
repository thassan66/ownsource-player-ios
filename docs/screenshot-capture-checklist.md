# Screenshot Capture Checklist

Use only fictional/demo library data. Do not capture real channels, sports, movies, provider names, copyrighted logos, private playlist URLs, usernames, passwords, or real stream sources.

## Devices

Capture both required families:

- iPhone
- iPad

Recommended local simulator set:

- iPhone 17 Pro
- iPad Pro 13-inch (M5)

## Reset And Demo Setup

1. Install the latest build.
2. Launch the app.
3. If existing data is present, open Settings and use Clear All Local Data.
4. Accept onboarding with the legal-use toggle.
5. Open Sources or Settings.
6. Tap Load Demo Library.
7. Confirm only fictional names are visible:
   - Harbour News
   - City Weather
   - Studio Fitness
   - Open Kitchen: Spring Menu
   - Design Notes S1 E1

For repeatable Simulator captures in a Debug build, launch with:

```sh
xcrun simctl launch booted com.gloudtechsolutions.ownsourceplayer -loadDemoLibrary -screenshotTab home
```

Supported screenshot tabs:

- `home`
- `live`
- `movies`
- `series`
- `sources`
- `settings`

## Screenshot Set

1. Home:
   - Show the demo hero and rails.
   - Avoid playback controls or external URLs.

2. Live:
   - Show fictional live channels and categories.
   - Confirm no real broadcaster logo or provider name is visible.

3. Movies:
   - Show fictional on-demand entries.
   - Confirm no real film title, poster, actor, or studio brand is visible.

4. Series:
   - Show fictional series grouping and episode list.
   - Confirm no real series title or artwork is visible.

5. Sources:
   - Show import options for M3U URL, local file, provider login, and XMLTV guide.
   - Do not enter real URLs or credentials.

6. Settings:
   - Show privacy, library counts, legal links, and parental controls.
   - Do not show private data.

## Optional Captions

Use short, safe captions in App Store Connect:

- Organize your own legal media sources
- Browse live channels from sources you provide
- Keep movies and episodes easy to find
- Import playlists and guide data privately
- Local controls for privacy and family use

Avoid these words and claims:

- Free TV
- Premium channels
- Sports access
- Watch movies free
- Provider included
- Subscription included
- IPTV service
