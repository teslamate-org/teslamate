import Foundation
import SwiftData

@Model
class CachedChargingSession {
    @Attribute(.unique) var sessionId: Int
    var carId: Int?
    var startDate: String?
    var endDate: String?
    var locationName: String?
    var chargeEnergyAdded: Double?
    var startBatteryLevel: Int?
    var endBatteryLevel: Int?
    var durationMin: Int?
    var cost: Double?
    var cachedAt: Date

    init(from session: ChargingSession) {
        self.sessionId = session.id
        self.carId = session.carId
        self.startDate = session.startDate
        self.endDate = session.endDate
        self.locationName = session.locationName
        self.chargeEnergyAdded = session.chargeEnergyAdded
        self.startBatteryLevel = session.startBatteryLevel
        self.endBatteryLevel = session.endBatteryLevel
        self.durationMin = session.durationMin
        self.cost = session.cost
        self.cachedAt = Date()
    }
}
