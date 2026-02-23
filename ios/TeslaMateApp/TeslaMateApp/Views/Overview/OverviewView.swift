import SwiftUI

struct OverviewView: View {
    let carId: Int
    @Environment(AppState.self) private var appState
    @State private var viewModel = OverviewViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary = viewModel.summary {
                    VStack(spacing: 16) {
                        // Vehicle Header
                        VStack(spacing: 4) {
                            Text(summary.displayName ?? appState.selectedCar?.displayName ?? "Tesla")
                                .font(.title2.bold())
                            if let model = summary.model {
                                Text("Model \(model)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // State Badge
                        StateBadgeView(state: summary.formattedState)

                        // Battery Gauge
                        BatteryGaugeView(
                            level: summary.batteryLevel ?? 0,
                            isCharging: summary.isCharging,
                            rangeKm: summary.rangeKm
                        )
                        .frame(height: 180)

                        // Info Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            if let temp = summary.outsideTemp {
                                InfoCard(title: "Outside", value: String(format: "%.1f\u{00B0}C", temp), icon: "thermometer")
                            }
                            if let temp = summary.insideTemp {
                                InfoCard(title: "Inside", value: String(format: "%.1f\u{00B0}C", temp), icon: "thermometer.sun")
                            }
                            if let odometer = summary.odometer {
                                InfoCard(title: "Odometer", value: String(format: "%.0f km", odometer), icon: "gauge.with.dots.needle.bottom.50percent")
                            }
                            if let version = summary.version {
                                InfoCard(title: "Software", value: version, icon: "arrow.down.app")
                            }
                            if let geofence = summary.geofence {
                                InfoCard(title: "Location", value: geofence, icon: "location.fill")
                            }
                            if let elevation = summary.elevation {
                                InfoCard(title: "Elevation", value: "\(elevation)m", icon: "mountain.2")
                            }
                        }
                        .padding(.horizontal)

                        // Status indicators
                        HStack(spacing: 16) {
                            StatusIcon(icon: "lock.fill", active: summary.locked == true, label: "Locked")
                            StatusIcon(icon: "shield.fill", active: summary.sentryMode == true, label: "Sentry")
                            StatusIcon(icon: "powerplug.fill", active: summary.pluggedIn == true, label: "Plugged In")
                            StatusIcon(icon: "fan.fill", active: summary.isClimateOn == true, label: "Climate")
                        }
                        .padding()
                    }
                    .padding()
                } else if viewModel.isLoading {
                    ProgressView("Loading vehicle data...")
                        .padding(.top, 100)
                } else if let error = viewModel.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.refresh(carId: carId) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 100)
                }
            }
            .refreshable {
                await viewModel.refresh(carId: carId)
            }
            .navigationTitle("Overview")
            .task {
                await viewModel.startListening(carId: carId)
            }
            .onDisappear {
                Task { await viewModel.stopListening() }
            }
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatusIcon: View {
    let icon: String
    let active: Bool
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(active ? .green : .gray)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
