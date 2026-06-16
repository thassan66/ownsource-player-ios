import AVKit
import SwiftUI
import UIKit

private enum PlaybackEngine {
    case native
    case vlc
}

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var channel: Channel

    @State private var player: AVPlayer?
    @State private var playbackError: String?
    @State private var playbackStatusMessage = "Buffering..."
    @State private var playbackNotice: String?
    @State private var isBuffering = false
    @State private var isPlaying = false
    @State private var playbackRate = 1.0
    @State private var areControlsVisible = true
    @State private var itemStatusObservation: NSKeyValueObservation?
    @State private var timeControlObservation: NSKeyValueObservation?
    @State private var failureObserver: NSObjectProtocol?
    @State private var endObserver: NSObjectProtocol?
    @State private var periodicTimeObserver: Any?
    @State private var startupWatchdogTask: Task<Void, Never>?
    @State private var retryTask: Task<Void, Never>?
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var candidateURLs: [URL] = []
    @State private var currentCandidateIndex = 0
    @State private var automaticRetryCount = 0
    @State private var lastResumePersistedAt: Double = 0
    @State private var playbackEngine: PlaybackEngine = .native

    private let playbackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private let maxAutomaticRetries = 2

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if playbackEngine == .vlc, let url = currentPlaybackURL {
                VLCPlayerContainerView(url: url, isPlaying: isPlaying)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }

                if areControlsVisible {
                    VLCPlayerChromeOverlay(
                        channel: channel,
                        isPlaying: isPlaying,
                        streamURL: url,
                        notice: playbackNotice,
                        closeAction: { dismiss() },
                        favoriteAction: { store.toggleFavorite(channel) },
                        playPauseAction: togglePlayPause,
                        stopAction: stopCurrent,
                        retryNativeAction: retryPlayback,
                        openExternalAction: openCurrentStreamExternally,
                        copyURLAction: copyCurrentStreamURL
                    )
                    .transition(.opacity)
                }
            } else if let player {
                PlayerContainerView(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }

                if areControlsVisible && playbackError == nil {
                    PlayerChromeOverlay(
                        channel: channel,
                        isPlaying: isPlaying,
                        playbackRate: playbackRate,
                        playbackRates: playbackRates,
                        closeAction: { dismiss() },
                        favoriteAction: { store.toggleFavorite(channel) },
                        playPauseAction: togglePlayPause,
                        stopAction: stopCurrent,
                        rewindAction: { skipCurrent(by: -10) },
                        forwardAction: { skipCurrent(by: 10) },
                        rateAction: setPlaybackRate
                    )
                    .transition(.opacity)
                }

                if isBuffering {
                    PlaybackStatusOverlay(message: playbackStatusMessage, systemImage: "hourglass")
                }

                if let playbackError {
                    PlaybackErrorOverlay(
                        message: playbackError,
                        streamURL: currentPlaybackURL,
                        notice: playbackNotice,
                        retry: retryPlayback,
                        tryVLC: shouldOfferManualVLC ? tryVLCFallbackManually : nil,
                        openExternal: openCurrentStreamExternally,
                        copyURL: copyCurrentStreamURL
                    )
                }
            } else {
                PlaybackPlaceholder(message: playbackError ?? "The stream URL is not valid.") {
                    retryPlayback()
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            saveResumePosition()
            tearDownPlaybackObservers()
        }
    }

    private func configurePlayer() {
        retryTask?.cancel()
        retryTask = nil
        tearDownPlaybackObservers(cancelPendingRetries: false)
        playbackError = nil
        playbackNotice = nil
        playbackStatusMessage = "Buffering..."
        isBuffering = true
        playbackRate = 1.0
        currentCandidateIndex = 0
        automaticRetryCount = 0
        playbackEngine = .native

        let urls = playbackCandidates(from: channel.streamURL)
        guard let url = urls.first else {
            playbackError = "The stream URL must be a valid HTTP or HTTPS address."
            isBuffering = false
            return
        }

        candidateURLs = urls
        if shouldUseExternalPlayback, let url = currentPlaybackURL {
            playbackError = "External playback is selected for movies and series."
            playbackNotice = "Opening \(url.host ?? "stream") in an external player."
            isBuffering = false
            isPlaying = false
            UIApplication.shared.open(url)
            store.markWatched(channel)
            return
        }

        if shouldStartWithVLC {
            playbackEngine = .vlc
            playbackStatusMessage = "Using VLC decoder..."
            isBuffering = false
            isPlaying = true
            store.markWatched(channel)
            scheduleControlsAutoHide()
            return
        }

        startPlayback(with: url, resumePosition: channel.resumePosition)
        store.markWatched(channel)
    }

    private func startPlayback(with url: URL, resumePosition: Double?) {
        tearDownPlaybackObservers(cancelPendingRetries: false)
        playbackError = nil
        playbackStatusMessage = "Buffering..."
        isBuffering = true

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": XtreamClient.mediaHTTPHeaders
        ])
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredForwardBufferDuration = channel.isOnDemand ? 12 : 2

        let configuredPlayer = AVPlayer(playerItem: item)
        configuredPlayer.automaticallyWaitsToMinimizeStalling = true
        observe(item: item, player: configuredPlayer)
        player = configuredPlayer

        if channel.isOnDemand, let resumePosition, resumePosition > 10 {
            configuredPlayer.seek(
                to: CMTime(seconds: resumePosition, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 1, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
            )
        }

        scheduleStartupWatchdog()
        playCurrent()
    }

    private func playbackCandidates(from value: String) -> [URL] {
        guard let primaryURL = MediaURLValidator.httpURL(from: value, defaultScheme: "http") else {
            return []
        }

        var urls = [primaryURL]

        for alternateExtension in alternateStreamExtensions(for: primaryURL) {
            if let alternateURL = replacingPathExtension(of: primaryURL, with: alternateExtension) {
                urls.append(alternateURL)
            }
        }

        if let alternateSchemeURL = alternateScheme(for: primaryURL) {
            urls.append(alternateSchemeURL)
            for alternateExtension in alternateStreamExtensions(for: alternateSchemeURL) {
                if let alternateURL = replacingPathExtension(of: alternateSchemeURL, with: alternateExtension) {
                    urls.append(alternateURL)
                }
            }
        }

        return deduplicated(urls)
    }

    private func alternateStreamExtensions(for url: URL) -> [String] {
        let lowercasedPath = url.path.lowercased()
        let currentExtension = url.pathExtension.lowercased()

        if channel.mediaKind == .live {
            if lowercasedPath.hasSuffix(".m3u8") {
                return ["ts"]
            }
            if lowercasedPath.hasSuffix(".ts") {
                return ["m3u8"]
            }
        }

        guard channel.isOnDemand else {
            return []
        }

        // Many IPTV panels report VOD as mkv/avi but can serve the same stream id as mp4 or HLS.
        let preferred = ["mp4", "m4v", "mov", "m3u8", "ts"]
        return preferred.filter { $0 != currentExtension }
    }

    private func replacingPathExtension(of url: URL, with extensionValue: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let path = components.percentEncodedPath
        guard let dotIndex = path.lastIndex(of: ".") else {
            return nil
        }

        components.percentEncodedPath = "\(path[..<path.index(after: dotIndex)])\(extensionValue)"
        return components.url
    }

    private func alternateScheme(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" else {
            return nil
        }

        components.scheme = "http"
        return components.url
    }

    private func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private var currentPlaybackURL: URL? {
        guard candidateURLs.indices.contains(currentCandidateIndex) else {
            return candidateURLs.first
        }
        return candidateURLs[currentCandidateIndex]
    }

    private func retryPlayback() {
        playbackNotice = nil
        configurePlayer()
    }

    private func openCurrentStreamExternally() {
        guard let url = currentPlaybackURL else {
            playbackNotice = "No stream URL is available to open."
            return
        }

        UIApplication.shared.open(url) { didOpen in
            if !didOpen {
                playbackNotice = "No app accepted this stream URL. Try Share Stream or Copy URL."
            }
        }
    }

    private func copyCurrentStreamURL() {
        guard let url = currentPlaybackURL else {
            playbackNotice = "No stream URL is available to copy."
            return
        }

        UIPasteboard.general.string = url.absoluteString
        playbackNotice = "Stream URL copied. Open it in VLC, Infuse, or another player that supports the movie codec."
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible.toggle()
        }
        scheduleControlsAutoHide()
    }

    private func showControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areControlsVisible = true
        }
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        guard isPlaying, playbackError == nil else {
            return
        }

        // Cancel any previous pending hide — only the latest tap/play should govern.
        controlsHideTask?.cancel()
        controlsHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return // Cancelled — a newer call took over
            }
            guard isPlaying, playbackError == nil else {
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                areControlsVisible = false
            }
        }
    }

    private func togglePlayPause() {
        isPlaying ? pauseCurrent() : playCurrent()
        showControls()
    }

    private func playCurrent() {
        if playbackEngine == .vlc {
            isPlaying = true
            scheduleControlsAutoHide()
            return
        }

        guard let player else {
            return
        }

        if channel.isOnDemand {
            player.playImmediately(atRate: Float(playbackRate))
        } else {
            player.play()
        }
        isPlaying = true
        scheduleControlsAutoHide()
    }

    private func pauseCurrent() {
        if playbackEngine == .vlc {
            isPlaying = false
            areControlsVisible = true
            return
        }

        player?.pause()
        isPlaying = false
        areControlsVisible = true
        saveResumePosition()
    }

    private func stopCurrent() {
        if playbackEngine == .vlc {
            isPlaying = false
            areControlsVisible = true
            return
        }

        player?.pause()
        player?.seek(to: .zero)
        if channel.isOnDemand {
            store.updateResumePosition(for: channel, seconds: 0, persistImmediately: true)
        }
        isPlaying = false
        areControlsVisible = true
    }

    private func setPlaybackRate(_ rate: Double) {
        playbackRate = rate
        if isPlaying, channel.isOnDemand {
            player?.rate = Float(rate)
        }
        showControls()
    }

    private func saveResumePosition() {
        guard channel.isOnDemand, let player else {
            return
        }

        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite else {
            return
        }

        store.updateResumePosition(for: channel, seconds: seconds, persistImmediately: true)
    }

    private func skipCurrent(by seconds: Double) {
        guard channel.isOnDemand, let player else {
            return
        }

        let currentSeconds = CMTimeGetSeconds(player.currentTime())
        guard currentSeconds.isFinite else {
            return
        }

        let targetSeconds = max(currentSeconds + seconds, 0)
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        showControls()
    }

    private func observe(item: AVPlayerItem, player: AVPlayer) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    startupWatchdogTask?.cancel()
                    startupWatchdogTask = nil
                    playbackError = nil
                    isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                case .failed:
                    handlePlaybackFailure(item.error, fallbackMessage: "The stream failed to load.")
                case .unknown:
                    isBuffering = true
                @unknown default:
                    handlePlaybackFailure(nil, fallbackMessage: "The stream entered an unknown playback state.")
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            Task { @MainActor in
                isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && playbackError == nil
                isPlaying = player.timeControlStatus == .playing
                if player.timeControlStatus != .playing {
                    areControlsVisible = true
                }
            }
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            handlePlaybackFailure(error, fallbackMessage: "Playback stopped because the stream failed.")
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            if channel.isOnDemand {
                Task { @MainActor in
                    store.updateResumePosition(for: channel, seconds: 0, persistImmediately: true)
                }
            }
            isPlaying = false
            areControlsVisible = true
        }

        addResumeTimeObserver(to: player)
    }

    private func scheduleStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled, isBuffering, playbackError == nil else {
                return
            }

            let timeoutMessage = "The stream did not start in time."
            if !scheduleAutomaticRecovery(after: timeoutMessage) {
                if activateVLCFallback(after: timeoutMessage) {
                    return
                }

                playbackError = "The stream did not start in time. Check the source URL or try again."
                isBuffering = false
                isPlaying = false
                areControlsVisible = true
            }
        }
    }

    private func handlePlaybackFailure(_ error: Error?, fallbackMessage: String) {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil

        let message = playbackFailureMessage(error, fallbackMessage: fallbackMessage)
        guard !scheduleAutomaticRecovery(after: message) else {
            return
        }

        if activateVLCFallback(after: message) {
            return
        }

        playbackError = message
        isBuffering = false
        isPlaying = false
        areControlsVisible = true
    }

    private func scheduleAutomaticRecovery(after message: String) -> Bool {
        guard !candidateURLs.isEmpty else {
            return false
        }

        let hasAlternateCandidate = currentCandidateIndex + 1 < candidateURLs.count
        guard hasAlternateCandidate || automaticRetryCount < maxAutomaticRetries else {
            return false
        }

        let resumePosition = channel.isOnDemand ? currentPlaybackSeconds() : nil
        let delay: UInt64

        if hasAlternateCandidate {
            currentCandidateIndex += 1
            automaticRetryCount = 0
            delay = 500_000_000
            playbackStatusMessage = "Trying another stream format..."
        } else {
            automaticRetryCount += 1
            delay = UInt64(automaticRetryCount) * 1_250_000_000
            playbackStatusMessage = "Retrying stream..."
        }

        let nextURL = candidateURLs[currentCandidateIndex]
        playbackError = nil
        isBuffering = true
        isPlaying = false
        areControlsVisible = true

        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                return
            }
            startPlayback(with: nextURL, resumePosition: resumePosition)
        }

        return true
    }

    private func playbackFailureMessage(_ error: Error?, fallbackMessage: String) -> String {
        guard let error else {
            return fallbackMessage
        }

        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return playbackFailureMessage(underlying, fallbackMessage: fallbackMessage)
        }

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "The device is offline. Check the connection and try again."
            case NSURLErrorTimedOut:
                return "The stream timed out. The app retried the source but it did not respond in time."
            case NSURLErrorUserAuthenticationRequired, NSURLErrorNoPermissionsToReadFile:
                return "The stream requires permission or the provider rejected access. Check the playlist/provider credentials."
            default:
                break
            }
        }

        if isUnsupportedMediaError(nsError) {
            let fallbackHint = shouldAllowVLCFallback
                ? "The app will try the VLC decoder next for wider IPTV codec support."
                : "Use Auto/VLC playback or install the VLC playback engine to add MKV, AVI, and wider codec support."
            return "This movie format is not supported by the native iOS player. \(fallbackHint)"
        }

        return error.localizedDescription.isEmpty ? fallbackMessage : error.localizedDescription
    }

    @discardableResult
    private func activateVLCFallback(after _: String) -> Bool {
        guard playbackEngine != .vlc,
              channel.isOnDemand,
              shouldAllowVLCFallback,
              currentPlaybackURL != nil else {
            return false
        }

        tearDownPlaybackObservers()
        playbackEngine = .vlc
        playbackError = nil
        playbackNotice = "Native playback failed. Using VLC decoder for wider IPTV codec support."
        playbackStatusMessage = "Using VLC decoder..."
        isBuffering = false
        isPlaying = true
        areControlsVisible = true
        scheduleControlsAutoHide()
        return true
    }

    private func tryVLCFallbackManually() {
        guard activateVLCFallback(after: playbackError ?? "Native playback failed.") else {
            playbackNotice = "VLC playback is not available in this build. Run pod install and open the generated workspace."
            return
        }
    }

    private var shouldAllowVLCFallback: Bool {
        channel.isOnDemand
            && VLCPlaybackSupport.isAvailable
            && store.playbackEnginePreference != .native
            && store.playbackEnginePreference != .externalForOnDemand
    }

    private var shouldOfferManualVLC: Bool {
        shouldAllowVLCFallback && playbackEngine != .vlc
    }

    private var shouldStartWithVLC: Bool {
        channel.isOnDemand
            && VLCPlaybackSupport.isAvailable
            && store.playbackEnginePreference == .vlcForOnDemand
    }

    private var shouldUseExternalPlayback: Bool {
        channel.isOnDemand && store.playbackEnginePreference == .externalForOnDemand
    }

    private func isUnsupportedMediaError(_ error: NSError) -> Bool {
        let unsupportedCodes: Set<Int> = [-12847, -12927, -11828, -11829]
        if unsupportedCodes.contains(error.code) {
            return true
        }

        return "\(error.domain) \(error.localizedDescription)"
            .localizedCaseInsensitiveContains("unsupported")
    }

    private func currentPlaybackSeconds() -> Double? {
        guard let player else {
            return nil
        }

        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : nil
    }

    private func addResumeTimeObserver(to player: AVPlayer) {
        guard channel.isOnDemand else {
            return
        }

        // Persist VOD progress while the user watches, not only when the player closes.
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 30, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite,
                  seconds >= 10,
                  abs(seconds - lastResumePersistedAt) >= 60 else {
                return
            }
            lastResumePersistedAt = seconds
            Task { @MainActor in
                store.updateResumePosition(for: channel, seconds: seconds)
            }
        }
    }

    private func tearDownPlaybackObservers(cancelPendingRetries: Bool = true) {
        if cancelPendingRetries {
            retryTask?.cancel()
            retryTask = nil
        }

        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil

        if let periodicTimeObserver, let player {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil

        itemStatusObservation?.invalidate()
        timeControlObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation = nil

        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        player?.pause()
        player = nil
        isPlaying = false
    }
}

private struct PlayerContainerView: UIViewControllerRepresentable {
    var player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

private struct PlayerChromeOverlay: View {
    @EnvironmentObject private var store: AppStore
    var channel: Channel
    var isPlaying: Bool
    var playbackRate: Double
    var playbackRates: [Double]
    var closeAction: () -> Void
    var favoriteAction: () -> Void
    var playPauseAction: () -> Void
    var stopAction: () -> Void
    var rewindAction: () -> Void
    var forwardAction: () -> Void
    var rateAction: (Double) -> Void

    private func formatEPGTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                IconButton(systemImage: "xmark", action: closeAction)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let current = store.currentProgram(for: channel) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Now: \(current.title)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            let now = Date()
                            let duration = current.endAt.timeIntervalSince(current.startAt)
                            let elapsed = now.timeIntervalSince(current.startAt)
                            let progress = duration > 0 ? max(0, min(1, elapsed / duration)) : 0.0

                            HStack(spacing: 6) {
                                ProgressView(value: progress)
                                    .tint(store.selectedTheme.accent)
                                    .frame(width: 60)
                                
                                let startStr = formatEPGTime(current.startAt)
                                let endStr = formatEPGTime(current.endAt)
                                Text("\(startStr) - \(endStr)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.72))
                                
                                let minutesLeft = Int(current.endAt.timeIntervalSince(now) / 60)
                                if minutesLeft > 0 {
                                    Text("(\(minutesLeft)m left)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(store.selectedTheme.accent)
                                }
                            }
                        }
                    } else {
                        Text("\(channel.category) - \(channel.mediaLabel)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }

                Spacer()

                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())

                IconButton(
                    systemImage: channel.isFavorite ? "star.fill" : "star",
                    tint: channel.isFavorite ? .yellow : .white,
                    action: favoriteAction
                )
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.78), .black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            HStack(spacing: 28) {
                if channel.isOnDemand {
                    OverlayControlButton(systemImage: "gobackward.10", size: 28, action: rewindAction)
                }

                OverlayControlButton(
                    systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill",
                    size: 58,
                    action: playPauseAction
                )

                if channel.isOnDemand {
                    OverlayControlButton(systemImage: "goforward.10", size: 28, action: forwardAction)
                }
            }
            .padding(.bottom, 22)

            HStack(spacing: 12) {
                if channel.isOnDemand {
                    Menu {
                        ForEach(playbackRates, id: \.self) { rate in
                            Button(rateLabel(rate)) {
                                rateAction(rate)
                            }
                        }
                    } label: {
                        Label(rateLabel(playbackRate), systemImage: "speedometer")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                Button(action: stopAction) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Spacer()

                Text(channel.isOnDemand ? "Scrub, PiP, AirPlay, subtitles, and audio tracks use the native player controls." : "Live stream")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func rateLabel(_ rate: Double) -> String {
        rate == 1.0 ? "1x" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))x"
    }
}

private struct VLCPlayerChromeOverlay: View {
    @EnvironmentObject private var store: AppStore
    var channel: Channel
    var isPlaying: Bool
    var streamURL: URL
    var notice: String?
    var closeAction: () -> Void
    var favoriteAction: () -> Void
    var playPauseAction: () -> Void
    var stopAction: () -> Void
    var retryNativeAction: () -> Void
    var openExternalAction: () -> Void
    var copyURLAction: () -> Void

    private func formatEPGTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                IconButton(systemImage: "xmark", action: closeAction)

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("VLC decoder")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.16))
                            .clipShape(Capsule())

                        Text(channel.mediaLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    
                    if let current = store.currentProgram(for: channel) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Now: \(current.title)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            let now = Date()
                            let duration = current.endAt.timeIntervalSince(current.startAt)
                            let elapsed = now.timeIntervalSince(current.startAt)
                            let progress = duration > 0 ? max(0, min(1, elapsed / duration)) : 0.0

                            HStack(spacing: 6) {
                                ProgressView(value: progress)
                                    .tint(store.selectedTheme.accent)
                                    .frame(width: 60)
                                
                                let startStr = formatEPGTime(current.startAt)
                                let endStr = formatEPGTime(current.endAt)
                                Text("\(startStr) - \(endStr)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.72))
                                
                                let minutesLeft = Int(current.endAt.timeIntervalSince(now) / 60)
                                if minutesLeft > 0 {
                                    Text("(\(minutesLeft)m left)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(store.selectedTheme.accent)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                IconButton(
                    systemImage: channel.isFavorite ? "star.fill" : "star",
                    tint: channel.isFavorite ? .yellow : .white,
                    action: favoriteAction
                )
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.82), .black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()

            VStack(spacing: 12) {
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack(spacing: 18) {
                    OverlayControlButton(
                        systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill",
                        size: 56,
                        action: playPauseAction
                    )

                    Button(action: stopAction) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(action: retryNativeAction) {
                        Label("Try Native", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                HStack(spacing: 10) {
                    ShareLink(item: streamURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(action: openExternalAction) {
                        Label("Open Externally", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(action: copyURLAction) {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .font(.caption.weight(.semibold))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

private struct IconButton: View {
    var systemImage: String
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct OverlayControlButton: View {
    var systemImage: String
    var size: CGFloat
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct PlaybackPlaceholder: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                title: "Cannot Play Stream",
                systemImage: "exclamationmark.triangle",
                message: message
            )

            Button {
                retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct PlaybackStatusOverlay: View {
    var message: String
    var systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .tint(.white)
    }
}

private struct PlaybackErrorOverlay: View {
    var message: String
    var streamURL: URL?
    var notice: String?
    var retry: () -> Void
    var tryVLC: (() -> Void)?
    var openExternal: () -> Void
    var copyURL: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)

            if let tryVLC {
                Button {
                    tryVLC()
                } label: {
                    Label("Try VLC Decoder", systemImage: "play.rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
            }

            if let streamURL {
                VStack(spacing: 8) {
                    ShareLink(item: streamURL) {
                        Label("Share Stream", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openExternal()
                    } label: {
                        Label("Open Externally", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyURL()
                    } label: {
                        Label("Copy Stream URL", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
    }
}

private extension Channel {
    var mediaLabel: String {
        switch mediaKind {
        case .live:
            return "Live"
        case .movie:
            return "Movie"
        case .seriesEpisode:
            return "Episode"
        }
    }
}
