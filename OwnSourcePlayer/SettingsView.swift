import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingResetConfirmation = false
    @State private var pinEntry = ""
    @State private var pinConfirmation = ""
    @State private var unlockEntry = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(
                                    store.selectedTheme.gradient
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("OwnSource Player")
                                    .font(.title3.bold())
                                Text("Private playlist player")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Privacy") {
                    Label("No app account is required.", systemImage: "person.crop.circle")
                    Label("Playlists are stored on this device.", systemImage: "internaldrive")
                    Label("No bundled content or providers.", systemImage: "checkmark.shield")
                }

                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { store.selectedTheme },
                        set: { store.selectTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.title, systemImage: theme == store.selectedTheme ? "checkmark.circle.fill" : "circle")
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    HStack(spacing: 10) {
                        ForEach(AppTheme.allCases) { theme in
                            Circle()
                                .fill(theme.gradient)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if theme == store.selectedTheme {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Library") {
                    NavigationLink {
                        SourceEditorView(standalone: false)
                    } label: {
                        Label("Manage Sources", systemImage: "folder.badge.plus")
                    }

                    HStack {
                        Text("Sources")
                        Spacer()
                        Text("\(store.sources.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Channels")
                        Spacer()
                        Text("\(store.library.liveChannels.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Movies")
                        Spacer()
                        Text("\(store.library.movies.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Series Episodes")
                        Spacer()
                        Text("\(store.library.seriesEpisodes.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Favorites")
                        Spacer()
                        Text("\(store.favoriteChannels.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("EPG Programmes")
                        Spacer()
                        Text("\(store.epgPrograms.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Preview Demo") {
                    Text("Load screenshot-safe fictional sources, channels, videos, and guide data to preview the finished app screens without using a real playlist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        store.loadDemoLibrary()
                    } label: {
                        Label("Load Demo Library", systemImage: "play.rectangle.on.rectangle")
                    }
                }

                Section("Parental Controls") {
                    SecureField("Set or update PIN", text: $pinEntry)
                        .keyboardType(.numberPad)
                        .onChange(of: pinEntry) { value in
                            pinEntry = value.filter(\.isNumber)
                        }

                    SecureField("Confirm PIN", text: $pinConfirmation)
                        .keyboardType(.numberPad)
                        .onChange(of: pinConfirmation) { value in
                            pinConfirmation = value.filter(\.isNumber)
                        }

                    Button {
                        store.parentalPIN = pinEntry
                        store.lockParentalControls()
                        pinEntry = ""
                        pinConfirmation = ""
                    } label: {
                        Label(store.parentalPIN.isEmpty ? "Enable PIN" : "Update PIN", systemImage: "lock")
                    }
                    .disabled(pinEntry.count < 4 || pinEntry != pinConfirmation)

                    if !store.parentalPIN.isEmpty {
                        if store.isParentalUnlocked {
                            Button {
                                store.lockParentalControls()
                            } label: {
                                Label("Lock Protected Categories", systemImage: "lock.fill")
                            }

                            Button(role: .destructive) {
                                store.parentalPIN = ""
                                store.protectedCategories = []
                                store.lockParentalControls()
                            } label: {
                                Label("Disable PIN", systemImage: "lock.slash")
                            }
                        } else {
                            SecureField("Enter PIN to unlock", text: $unlockEntry)
                                .keyboardType(.numberPad)
                                .onChange(of: unlockEntry) { value in
                                    unlockEntry = value.filter(\.isNumber)
                                }

                            Button {
                                if store.unlockParentalControls(pin: unlockEntry) {
                                    unlockEntry = ""
                                } else {
                                    store.alertMessage = "Incorrect PIN."
                                }
                            } label: {
                                Label("Unlock", systemImage: "lock.open")
                            }
                            .disabled(unlockEntry.isEmpty)
                        }

                        if store.isParentalUnlocked {
                            ForEach(store.protectableCategories(), id: \.self) { category in
                                Toggle(category, isOn: Binding(
                                    get: { store.protectedCategories.contains(category) },
                                    set: { store.setCategoryProtection(category, isProtected: $0) }
                                ))
                            }
                        } else if !store.protectedCategories.isEmpty {
                            Text("\(store.protectedCategories.count) protected categories are hidden while parental controls are locked.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Legal") {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }

                    NavigationLink {
                        TermsOfUseView()
                    } label: {
                        Label("Terms of Use", systemImage: "doc.text")
                    }

                    Text("OwnSource Player is a media player only. It does not provide channels, playlists, subscriptions, or third-party media services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        isShowingResetConfirmation = true
                    } label: {
                        Label("Clear All Local Data", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .listStyle(.insetGrouped)
            .confirmationDialog("Clear all local data?", isPresented: $isShowingResetConfirmation, titleVisibility: .visible) {
                Button("Clear Data", role: .destructive) {
                    store.clearAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes saved sources, channels, favorites, and onboarding acceptance from this device.")
            }
        }
    }
}
