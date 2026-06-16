# VLC Playback Fallback

The app uses `AVPlayer` first for native HLS/MP4 playback, AirPlay, PiP, and system controls. Some IPTV movie and series streams use containers or codecs that `AVPlayer` rejects with errors such as `OSStatus -12847`. Similar IPTV apps usually handle those streams with a VLC/FFmpeg-based decoder.

This project includes an optional MobileVLCKit fallback:

1. Run `pod install` from the repository root.
2. Open `OwnSourcePlayer.xcworkspace`, not `OwnSourcePlayer.xcodeproj`.
3. Build and run the `OwnSourcePlayer` scheme.

When MobileVLCKit is installed, movie and series playback will still start with `AVPlayer`. If native playback exhausts retries and format fallbacks, the app switches to the VLC decoder automatically. The error overlay also exposes a manual `Try VLC Decoder` action when the VLC engine is available.

Without MobileVLCKit installed, the app keeps building with the native player only and shows a message explaining that VLC fallback is not present in that build.
