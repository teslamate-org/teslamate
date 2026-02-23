import Foundation
import CoreLocation

struct Position: Codable, Identifiable {
    let id: Int
    let date: String?
    let latitude: Double?
    let longitude: Double?
    let elevation: Int?
    let speed: Int?
    let power: Int?
    let odometer: Double?
    let batteryLevel: Int?
    let usableBatteryLevel: Int?
    let idealBatteryRangeKm: Double?
    let estBatteryRangeKm: Double?
    let ratedBatteryRangeKm: Double?
    let outsideTemp: Double?
    let insideTemp: Double?
    let fanStatus: Int?
    let isClimateOn: Bool?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
