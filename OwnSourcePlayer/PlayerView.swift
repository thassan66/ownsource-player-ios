import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var channel: Channel

    @State private var player: AVPlayer?
    @State private var playbackError: String?
    @State private var isBuffering = false
    @State private var isPlaying = false
    @State private var playbackRate = 1.0
    @State private var areControlsVisible = true
    @State private var itemStatusObservation: NSKeyValueObservation?
    @State private var timeControlObservation: NSKeyValueObservation?
    @State private var failureObserver: NSObjectProtocol?
    @State private var endObserver: NSObjectProtocol?
    @State private var periodicTimeObserver: Any?

    private let playbackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player {
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
                    PlaybackStatusOverlay(message: "Buffering...", systemImage: "hourglass")
                }

                if let playbackError {
                    PlaybackErrorOverlay(message: playbackError) {
                        retryPlayback()
                    }
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
        tearDownPlaybackObservers()
        playbackError = nil
        isBuffering = true
        playbackRate = 1.0

        guard let url = playbackURL(from: channel.streamURL) else {
            playbackError = "The stream URL must be a valid HTTP or HTTPS address."
            isBuffering = false
            return
        }

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": XtreamClient.mediaHTTPHeaders
        ])
        let item = AVPlayerItem(asset: asset)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredForwardBufferDuration = channel.isOnDemand ? 8 : 3

        let configuredPlayer = AVPlayer(playerItem: item)
        configuredPlayer.automaticallyWaitsToMinimizeStalling = true
        observe(item: item, player: configuredPlayer)
        player = configuredPlayer

        if channel.isOnDemand, let resumePosition = channel.resumePosition, resumePosition > 10 {
            configuredPlayer.seek(to: CMTime(seconds: resumePosition, preferredTimescale: 600))
        }

        playCurrent()
        store.markWatched(channel)
    }

    private func playbackURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private func retryPlayback() {
        configurePlayer()
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

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
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
        player?.pause()
        isPlaying = false
        areControlsVisible = true
        saveResumePosition()
    }

    private func stopCurrent() {
        player?.pause()
        player?.seek(to: .zero)
        if channel.isOnDemand {
            store.updateResumePosition(for: channel, seconds: 0)
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

        store.updateResumePosition(for: channel, seconds: seconds)
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
                    playbackError = nil
                    isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                case .failed:
                    playbackError = item.error?.localizedDescription ?? "The stream failed to load."
                    isBuffering = false
                    isPlaying = false
                case .unknown:
                    isBuffering = true
                @unknown default:
                    playbackError = "The stream entered an unknown playback state."
                    isBuffering = false
                    isPlaying = false
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
            playbackError = error?.localizedDescription ?? "Playback stopped because the stream failed."
            isBuffering = false
            isPlaying = false
            areControlsVisible = true
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            if channel.isOnDemand {
                Task { @MainActor in
                    store.updateResumePosition(for: channel, seconds: 0)
                }
            }
            isPlaying = false
            areControlsVisible = true
        }

        addResumeTimeObserver(to: player)
    }

    private func addResumeTimeObserver(to player: AVPlayer) {
        guard channel.isOnDemand else {
            return
        }

        // Persist VOD progress while the user watches, not only when the player closes.
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 15, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds >= 10 else {
                return
            }
            Task { @MainActor in
                store.updateResumePosition(for: channel, seconds: seconds)
            }
        }
    }

    private func tearDownPlaybackObservers() {
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

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                IconButton(systemImage: "xmark", action: closeAction)

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(channel.category) - \(channel.mediaLabel)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
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
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button {
                retry()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: 320)
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
