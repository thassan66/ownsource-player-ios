import SwiftUI

@main
struct OwnSourcePlayerApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-loadDemoLibrary") {
                        store.loadDemoLibrary()
                    }
                    #endif
                }
        }
    }
}
