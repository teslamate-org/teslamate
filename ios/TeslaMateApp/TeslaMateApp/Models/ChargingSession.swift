import Foundation

struct ChargingSession: Codable, Identifiable {
    let id: Int
    let carId: Int?
    let startDate: String?
    let endDate: String?
    let address: AddressInfo?
    let geofence: GeofenceInfo?
    let chargeEnergyAdded: Double?
    let chargeEnergyUsed: Double?
    let startIdealRangeKm: Double?
    let endIdealRangeKm: Double?
    let startRatedRangeKm: Double?
    let endRatedRangeKm: Double?
    let startBatteryLevel: Int?
    let endBatteryLevel: Int?
    let durationMin: Int?
    let outsideTempAvg: Double?
    let cost: Double?

    var locationName: String {
        geofence?.name ?? address?.displayName ?? "Unknown"
    }

    var formattedEnergy: String {
        guard let energy = chargeEnergyAdded else { return "--" }
        return String(format: "%.1f kWh", energy)
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

    var formattedCost: String {
        guard let cost else { return "--" }
        return String(format: "$%.2f", cost)
    }

    var socChange: String {
        guard let start = startBatteryLevel, let end = endBatteryLevel else { return "--" }
        return "\(start)% → \(end)%"
    }
}

struct ChargeDataPoint: Codable, Identifiable {
    let id: Int
    let date: String?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let chargeEnergyAdded: Double?
    let chargerActualCurrent: Int?
    let chargerPhases: Int?
    let chargerPilotCurrent: Int?
    let chargerPower: Int?
    let chargerVoltage: Int?
    let idealBatteryRangeKm: Double?
    let ratedBatteryRangeKm: Double?
    let outsideTemp: Double?
    let fastChargerPresent: Bool?
    let fastChargerBrand: String?
    let fastChargerType: String?
    let connChargeCable: String?

    var parsedDate: Date? {
        guard let date else { return nil }
        return ISO8601DateFormatter().date(from: date)
    }
}
