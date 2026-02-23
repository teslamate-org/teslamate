import SwiftUI

struct ChargeRowView: View {
    let charge: ChargingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Location
            Text(charge.locationName)
                .font(.subheadline.weight(.medium))

            // SOC change bar
            HStack(spacing: 8) {
                if let start = charge.startBatteryLevel, let end = charge.endBatteryLevel {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(end) / 100.0)
                        }
                    }
                    .frame(height: 8)

                    Text(charge.socChange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Stats
            HStack(spacing: 16) {
                Label(charge.formattedEnergy, systemImage: "bolt.fill")
                Label(charge.formattedDuration, systemImage: "clock")
                if charge.cost != nil {
                    Label(charge.formattedCost, systemImage: "dollarsign.circle")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Date
            if let dateStr = charge.startDate {
                Text(formatDate(dateStr))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
    }
}
