import SwiftUI

struct BatteryGaugeView: View {
    let level: Int
    let isCharging: Bool
    let rangeKm: Double?

    private var color: Color {
        if level > 50 { return .green }
        if level > 20 { return .yellow }
        return .red
    }

    private var progress: Double {
        Double(level) / 100.0
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 16)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: level)

                // Center content
                VStack(spacing: 4) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    }
                    Text("\(level)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    if let range = rangeKm {
                        Text(String(format: "%.0f km", range))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }
}
