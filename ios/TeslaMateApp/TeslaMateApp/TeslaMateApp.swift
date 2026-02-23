import SwiftUI
import SwiftData

@main
struct TeslaMateApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.checkAuth()
                }
        }
    }
}
