import SwiftUI

struct StateBadgeView: View {
    let state: String

    private var color: Color {
        switch state.lowercased() {
        case "driving": return .blue
        case "charging": return .green
        case "online": return .teal
        case "asleep", "sleeping": return .purple
        case "offline": return .gray
        case "suspended": return .orange
        case "updating": return .yellow
        default: return .secondary
        }
    }

    private var icon: String {
        switch state.lowercased() {
        case "driving": return "car.fill"
        case "charging": return "bolt.fill"
        case "online": return "wifi"
        case "asleep", "sleeping": return "moon.fill"
        case "offline": return "wifi.slash"
        case "suspended": return "pause.circle.fill"
        case "updating": return "arrow.down.circle.fill"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(state)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(20)
    }
}
