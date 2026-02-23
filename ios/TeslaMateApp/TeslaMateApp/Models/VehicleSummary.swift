import Foundation

struct VehicleSummary: Codable {
    let displayName: String?
    let state: String?
    let since: String?
    let healthy: Bool?
    let latitude: Double?
    let longitude: Double?
    let heading: Int?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let chargingState: String?
    let idealBatteryRangeKm: Double?
    let estBatteryRangeKm: Double?
    let ratedBatteryRangeKm: Double?
    let chargeEnergyAdded: Double?
    let chargeLimitSoc: Int?
    let chargePortDoorOpen: Bool?
    let chargerActualCurrent: Int?
    let chargerPhases: Int?
    let chargerPower: Int?
    let chargerVoltage: Int?
    let chargeCurrentRequest: Int?
    let chargeCurrentRequestMax: Int?
    let timeToFullCharge: Double?
    let scheduledChargingStartTime: String?
    let speed: Int?
    let power: Int?
    let shiftState: String?
    let outsideTemp: Double?
    let insideTemp: Double?
    let isClimateOn: Bool?
    let isPreconditioning: Bool?
    let climateKeeperMode: String?
    let odometer: Double?
    let locked: Bool?
    let sentryMode: Bool?
    let pluggedIn: Bool?
    let windowsOpen: Bool?
    let doorsOpen: Bool?
    let trunkOpen: Bool?
    let frunkOpen: Bool?
    let isUserPresent: Bool?
    let elevation: Int?
    let geofence: String?
    let model: String?
    let trimBadging: String?
    let exteriorColor: String?
    let wheelType: String?
    let spoilerType: String?
    let version: String?
    let updateAvailable: Bool?
    let updateVersion: String?
    let tpmsPressureFl: Double?
    let tpmsPressureFr: Double?
    let tpmsPressureRl: Double?
    let tpmsPressureRr: Double?
    let activeRouteDestination: String?
    let activeRouteLatitude: Double?
    let activeRouteLongitude: Double?
    let activeRouteEnergyAtArrival: Double?
    let activeRouteMilesToArrival: Double?
    let activeRouteMinutesToArrival: Double?
    let centerDisplayState: Int?

    var formattedState: String {
        guard let state else { return "Unknown" }
        return state.capitalized
    }

    var batteryColor: String {
        guard let level = batteryLevel else { return "gray" }
        if level > 50 { return "green" }
        if level > 20 { return "yellow" }
        return "red"
    }

    var isCharging: Bool {
        state == "charging"
    }

    var isDriving: Bool {
        state == "driving"
    }

    var rangeKm: Double? {
        ratedBatteryRangeKm ?? idealBatteryRangeKm ?? estBatteryRangeKm
    }
}
