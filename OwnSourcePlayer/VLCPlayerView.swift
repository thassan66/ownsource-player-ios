import SwiftUI
import UIKit

#if canImport(MobileVLCKit)
import MobileVLCKit

struct VLCPlayerContainerView: UIViewRepresentable {
    var url: URL
    var isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        context.coordinator.attach(to: view, url: url, isPlaying: isPlaying)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(to: uiView, url: url, isPlaying: isPlaying)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private let player = VLCMediaPlayer()
        private var currentURL: URL?
        private var lastIsPlaying: Bool?
        private weak var attachedView: UIView?

        func attach(to view: UIView, url: URL, isPlaying: Bool) {
            // Only reassign drawable when the view reference changes.
            // Previously this was set unconditionally on every SwiftUI update,
            // triggering a VLC render-pipeline reset and causing unnecessary flicker.
            if attachedView !== view {
                attachedView = view
                player.drawable = view
            }

            if currentURL != url {
                currentURL = url
                lastIsPlaying = nil

                let media = VLCMedia(url: url)
                VLCMediaOptions.apply(to: media)
                player.media = media
            }

            guard lastIsPlaying != isPlaying else {
                return
            }

            if isPlaying {
                player.play()
            } else {
                player.pause()
            }
            lastIsPlaying = isPlaying
        }

        func stop() {
            player.stop()
            player.drawable = nil
            attachedView = nil
            currentURL = nil
            lastIsPlaying = nil
        }
    }
}

enum VLCPlaybackSupport {
    static let isAvailable = true
}

private enum VLCMediaOptions {
    static func apply(to media: VLCMedia) {
        let options = [
            ":network-caching=1800",
            ":live-caching=1800",
            ":file-caching=1000",
            ":clock-jitter=0"
        ]

        for option in options {
            media.addOption(option)
        }

        if let userAgent = XtreamClient.mediaHTTPHeaders["User-Agent"], !userAgent.isEmpty {
            media.addOption(":http-user-agent=\(userAgent)")
        }
    }
}
#else
struct VLCPlayerContainerView: View {
    var url: URL
    var isPlaying: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash")
                .font(.largeTitle)
                .foregroundStyle(.white)

            Text("VLC playback is not installed in this build.")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Install MobileVLCKit with CocoaPods to enable wider IPTV movie and series codec support.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 340)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

enum VLCPlaybackSupport {
    static let isAvailable = false
}
#endif
