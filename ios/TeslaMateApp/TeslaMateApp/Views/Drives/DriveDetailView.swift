import SwiftUI
import MapKit

struct DriveDetailView: View {
    let driveId: Int
    @State private var drive: Drive?
    @State private var positions: [Position] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading drive details...")
                    .padding(.top, 100)
            } else if let drive {
                VStack(spacing: 16) {
                    // Map
                    if !positions.isEmpty {
                        DriveMapView(positions: positions)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }

                    // Route info
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("From")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(drive.startDisplayName)
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text("To")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(drive.endDisplayName)
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Distance", value: drive.formattedDistance)
                        StatCard(title: "Duration", value: drive.formattedDuration)
                        if let speedMax = drive.speedMax {
                            StatCard(title: "Max Speed", value: "\(speedMax) km/h")
                        }
                        if let powerMax = drive.powerMax {
                            StatCard(title: "Max Power", value: "\(powerMax) kW")
                        }
                        if let temp = drive.outsideTempAvg {
                            StatCard(title: "Avg Outside Temp", value: String(format: "%.1f\u{00B0}C", temp))
                        }
                        if let ascent = drive.ascent, let descent = drive.descent {
                            StatCard(title: "Elevation", value: "+\(ascent)m / -\(descent)m")
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                    Button("Retry") { Task { await loadData() } }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 100)
            }
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        do {
            let result = try await APIClient.shared.getDriveWithPositions(id: driveId)
            await MainActor.run {
                self.drive = result.drive
                self.positions = result.positions
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
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
