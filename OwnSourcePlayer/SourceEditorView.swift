import SwiftUI
import UniformTypeIdentifiers

struct SourceEditorView: View {
    var standalone = true

    var body: some View {
        if standalone {
            NavigationStack {
                SourceEditorContent()
            }
        } else {
            SourceEditorContent()
        }
    }
}

private struct SourceEditorContent: View {
    @EnvironmentObject private var store: AppStore
    @State private var sourceName = ""
    @State private var playlistURL = ""
    @State private var providerName = ""
    @State private var providerServer = ""
    @State private var providerUsername = ""
    @State private var providerPassword = ""
    @State private var epgURL = ""
    @State private var isFileImporterPresented = false

    var body: some View {
        List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Library Setup", systemImage: "folder.badge.plus")
                            .font(.title3.bold())
                        Text("Add legal playlists, provider logins, and XMLTV guide data. Provider passwords are stored securely in Keychain.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if store.sources.isEmpty {
                    Section("Preview Demo") {
                        Text("Load screenshot-safe fictional sources, channels, videos, and guide data to preview the app without a real playlist.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            store.loadDemoLibrary()
                        } label: {
                            Label("Load Demo Library", systemImage: "play.rectangle.on.rectangle")
                        }
                    }
                }

                Section("Add M3U URL") {
                    TextField("Source name", text: $sourceName)
                        .textContentType(.name)

                    TextField("https://example.com/playlist.m3u", text: $playlistURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await store.importRemoteSource(name: sourceName, urlString: playlistURL)
                            if store.alertMessage == nil {
                                sourceName = ""
                                playlistURL = ""
                            }
                        }
                    } label: {
                        Label("Add URL Source", systemImage: "plus.circle")
                    }
                    .disabled(playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Import File") {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label("Choose M3U File", systemImage: "doc.badge.plus")
                    }
                }

                Section("Add Provider Login") {
                    TextField("Source name", text: $providerName)
                        .textContentType(.name)

                    TextField("https://example.com:8080", text: $providerServer)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Username", text: $providerUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $providerPassword)

                    Button {
                        Task {
                            await store.importXtreamSource(
                                name: providerName,
                                server: providerServer,
                                username: providerUsername,
                                password: providerPassword
                            )
                            if store.alertMessage == nil {
                                providerName = ""
                                providerServer = ""
                                providerUsername = ""
                                providerPassword = ""
                            }
                        }
                    } label: {
                        Label("Add Provider Source", systemImage: "person.badge.key")
                    }
                    .disabled(providerServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                #if DEBUG
                if PrivateProviderConfig.isConfigured {
                    Section("Internal Provider") {
                        Text("Imports the local private provider preset from this Mac-only build.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await store.importXtreamSource(
                                    name: PrivateProviderConfig.name,
                                    server: PrivateProviderConfig.server,
                                    username: PrivateProviderConfig.username,
                                    password: PrivateProviderConfig.password
                                )
                            }
                        } label: {
                            Label("Import Internal Provider", systemImage: "lock.shield")
                        }
                    }
                }
                #endif

                Section("Add EPG Guide") {
                    TextField("https://example.com/guide.xml", text: $epgURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task {
                            await store.importEPG(urlString: epgURL)
                            if store.alertMessage == nil {
                                epgURL = ""
                            }
                        }
                    } label: {
                        Label("Import XMLTV Guide", systemImage: "calendar.badge.plus")
                    }
                    .disabled(epgURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let guide = store.epgGuideSource {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Saved Guide")
                                .font(.headline)
                            Text(guide.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let lastRefreshAt = guide.lastRefreshAt {
                                Text("Updated \(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            Task {
                                await store.refreshEPG()
                            }
                        } label: {
                            Label("Refresh XMLTV Guide", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            store.clearEPG()
                        } label: {
                            Label("Remove Guide", systemImage: "trash")
                        }
                    }
                }

                Section("Saved Sources") {
                    if store.sources.isEmpty {
                        Text("No sources added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.sources) { source in
                            SourceRow(source: source)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                store.deleteSource(store.sources[index])
                            }
                        }
                    }
                }
        }
        .navigationTitle("Sources")
        .listStyle(.insetGrouped)
        .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await store.importLocalFile(url: url)
                    }
                }
            case .failure(let error):
                store.alertMessage = error.localizedDescription
            }
        }
    }
}

private struct SourceRow: View {
    @EnvironmentObject private var store: AppStore
    var source: MediaSource

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: source.kind == .xtream ? "person.badge.key.fill" : "folder.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(store.selectedTheme.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.headline)
                    Text(source.kind.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(source.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastRefreshAt = source.lastRefreshAt {
                    Text("Updated \(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if source.kind == .m3uURL || source.kind == .xtream {
                if source.kind == .xtream {
                    NavigationLink {
                        ProviderHealthView(source: source)
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Provider health")
                }

                Button {
                    Task {
                        await store.refresh(source: source)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh source")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderHealthView: View {
    @EnvironmentObject private var store: AppStore
    var source: MediaSource

    private var report: ProviderHealthReport? {
        store.providerHealthReport(for: source)
    }

    private var isChecking: Bool {
        store.isCheckingProviderHealth(source)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(source.name, systemImage: "person.badge.key.fill")
                        .font(.headline)
                    Text(source.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }

            Section("Endpoint Status") {
                if let report {
                    ForEach(report.endpoints) { endpoint in
                        ProviderEndpointHealthRow(endpoint: endpoint)
                    }
                } else {
                    Text("Run a health check to test account, live, movies, series, and M3U endpoints.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let report {
                Section("Last Check") {
                    HStack {
                        Text("Checked")
                        Spacer()
                        Text(report.checkedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Reachable endpoints")
                        Spacer()
                        Text("\(report.endpoints.filter { $0.status == .ok }.count)/\(report.endpoints.count)")
                            .foregroundStyle(report.isHealthy ? .green : .red)
                    }
                }
            }
        }
        .navigationTitle("Provider Health")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.checkProviderHealth(source: source)
                    }
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Label("Check", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isChecking)
            }
        }
        .task {
            if report == nil {
                await store.checkProviderHealth(source: source)
            }
        }
    }
}

private struct ProviderEndpointHealthRow: View {
    var endpoint: ProviderEndpointHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(endpoint.name, systemImage: statusImage)
                    .foregroundStyle(statusColor)
                Spacer()
                Text(endpoint.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                if let itemCount = endpoint.itemCount {
                    Label("\(itemCount) items", systemImage: "number")
                }
                if let responseTime = endpoint.responseTime {
                    Label(responseTime.formatted(.number.precision(.fractionLength(1))) + "s", systemImage: "timer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let message = endpoint.message, endpoint.status != .ok {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusImage: String {
        switch endpoint.status {
        case .ok:
            return "checkmark.circle.fill"
        case .empty:
            return "circle.dashed"
        case .timedOut:
            return "clock.badge.exclamationmark"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch endpoint.status {
        case .ok:
            return .green
        case .empty:
            return .orange
        case .timedOut:
            return .orange
        case .failed:
            return .red
        }
    }
}
