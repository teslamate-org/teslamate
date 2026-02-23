import Foundation

struct Drive: Codable, Identifiable {
    let id: Int
    let carId: Int?
    let startDate: String?
    let endDate: String?
    let startAddress: AddressInfo?
    let endAddress: AddressInfo?
    let startGeofence: GeofenceInfo?
    let endGeofence: GeofenceInfo?
    let distance: Double?
    let durationMin: Int?
    let speedMax: Int?
    let powerMax: Int?
    let powerMin: Int?
    let startKm: Double?
    let endKm: Double?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let startRatedRangeKm: Double?
    let endRatedRangeKm: Double?
    let outsideTempAvg: Double?
    let insideTempAvg: Double?
    let ascent: Int?
    let descent: Int?

    var startDisplayName: String {
        startGeofence?.name ?? startAddress?.displayName ?? "Unknown"
    }

    var endDisplayName: String {
        endGeofence?.name ?? endAddress?.displayName ?? "Unknown"
    }

    var formattedDistance: String {
        guard let distance else { return "--" }
        return String(format: "%.1f km", distance)
    }

    var formattedDuration: String {
        guard let durationMin else { return "--" }
        let hours = durationMin / 60
        let minutes = durationMin % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var rangeUsed: Double? {
        guard let start = startRatedRangeKm, let end = endRatedRangeKm else { return nil }
        return start - end
    }
}

struct AddressInfo: Codable {
    let id: Int?
    let displayName: String?
    let city: String?
    let county: String?
    let country: String?
    let state: String?
    let road: String?
    let houseNumber: String?
}

struct GeofenceInfo: Codable {
    let id: Int?
    let name: String?
}
