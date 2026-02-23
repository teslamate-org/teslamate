import SwiftUI
import Charts

struct ChargeDetailView: View {
    let chargeId: Int
    @State private var chargingSession: ChargingSession?
    @State private var charges: [ChargeDataPoint] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading charge details...")
                    .padding(.top, 100)
            } else if let session = chargingSession {
                VStack(spacing: 16) {
                    // Location
                    VStack(spacing: 4) {
                        Text(session.locationName)
                            .font(.title3.bold())
                        Text(session.socChange)
                            .font(.headline)
                            .foregroundColor(.green)
                    }

                    // Charge curve chart
                    if !charges.isEmpty {
                        ChargeCurveChart(charges: charges)
                            .frame(height: 250)
                            .padding(.horizontal)
                    }

                    // Stats grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCard(title: "Energy Added", value: session.formattedEnergy)
                        StatCard(title: "Duration", value: session.formattedDuration)

                        if let cost = session.cost {
                            StatCard(title: "Cost", value: String(format: "$%.2f", cost))
                        }
                        if let temp = session.outsideTempAvg {
                            StatCard(title: "Avg Temp", value: String(format: "%.1f\u{00B0}C", temp))
                        }
                        if let startRange = session.startRatedRangeKm, let endRange = session.endRatedRangeKm {
                            StatCard(title: "Range Added", value: String(format: "%.0f km", endRange - startRange))
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
        .navigationTitle("Charge Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        do {
            let result = try await APIClient.shared.getChargeDetail(id: chargeId)
            await MainActor.run {
                self.chargingSession = result.chargingProcess
                self.charges = result.charges
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
