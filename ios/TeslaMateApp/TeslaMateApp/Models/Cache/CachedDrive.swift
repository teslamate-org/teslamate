import Foundation
import SwiftData

@Model
class CachedDrive {
    @Attribute(.unique) var driveId: Int
    var carId: Int?
    var startDate: String?
    var endDate: String?
    var startAddressName: String?
    var endAddressName: String?
    var distance: Double?
    var durationMin: Int?
    var speedMax: Int?
    var cachedAt: Date

    init(from drive: Drive) {
        self.driveId = drive.id
        self.carId = drive.carId
        self.startDate = drive.startDate
        self.endDate = drive.endDate
        self.startAddressName = drive.startAddress?.displayName
        self.endAddressName = drive.endAddress?.displayName
        self.distance = drive.distance
        self.durationMin = drive.durationMin
        self.speedMax = drive.speedMax
        self.cachedAt = Date()
    }
}
