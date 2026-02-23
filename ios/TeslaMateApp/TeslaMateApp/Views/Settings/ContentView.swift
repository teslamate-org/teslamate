import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                SettingsView()
            }
        }
    }
}
