import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Group {
                if let car = appState.selectedCar {
                    OverviewView(carId: car.id)
                } else {
                    ProgressView("Loading...")
                }
            }
            .tabItem {
                Label("Overview", systemImage: "car.fill")
            }

            Group {
                if let car = appState.selectedCar {
                    DrivesListView(carId: car.id)
                } else {
                    ProgressView("Loading...")
                }
            }
            .tabItem {
                Label("Drives", systemImage: "road.lanes")
            }

            Group {
                if let car = appState.selectedCar {
                    ChargesListView(carId: car.id)
                } else {
                    ProgressView("Loading...")
                }
            }
            .tabItem {
                Label("Charges", systemImage: "bolt.fill")
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}
