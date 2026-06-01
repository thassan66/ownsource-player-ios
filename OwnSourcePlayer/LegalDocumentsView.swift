import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(title: "Privacy Policy") {
            LegalSection(
                title: "No Account",
                text: "OwnSource Player does not require an app account and does not include an app-operated media service."
            )

            LegalSection(
                title: "Local Library Data",
                text: "Sources, channel lists, favorites, recently watched items, parental category settings, and imported guide data are stored on this device. Provider passwords and parental control PINs are stored in the device Keychain."
            )

            LegalSection(
                title: "Network Requests",
                text: "The app contacts only the source URLs, guide URLs, and provider servers that you enter. Those services may receive your IP address and request details according to their own policies."
            )

            LegalSection(
                title: "No Bundled Content",
                text: "The app does not provide channels, playlists, subscriptions, or copyrighted media. You are responsible for using only sources you have the legal right to access."
            )

            LegalSection(
                title: "Data Removal",
                text: "Use Clear All Local Data in Settings to remove saved sources, channels, guide data, favorites, parental settings, and stored provider credentials from this device."
            )
        }
    }
}

struct TermsOfUseView: View {
    var body: some View {
        LegalDocumentView(title: "Terms of Use") {
            LegalSection(
                title: "Personal Media Player",
                text: "OwnSource Player is a media player for user-provided sources. It is not a TV provider, streaming subscription, playlist marketplace, or content service."
            )

            LegalSection(
                title: "Legal Source Requirement",
                text: "Only add playlists, streams, guide data, and provider logins that you own or have permission to use. Do not use the app to access unauthorized media."
            )

            LegalSection(
                title: "No Content Warranty",
                text: "Playback quality, availability, programme data, and source reliability depend on the source you provide. The app cannot guarantee that third-party streams or guides will work."
            )

            LegalSection(
                title: "Parental Controls",
                text: "Parental controls are a local convenience feature and are not a substitute for device-level restrictions, supervision, or legal compliance."
            )

            LegalSection(
                title: "Responsibility",
                text: "You are responsible for the sources you add, the media you access, and compliance with applicable laws and service terms."
            )
        }
    }
}

private struct LegalDocumentView<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
                Text("Last updated: May 31, 2026")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegalSection: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
