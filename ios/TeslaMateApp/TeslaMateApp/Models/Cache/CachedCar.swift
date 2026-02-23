import Foundation
import SwiftData

@Model
class CachedCar {
    @Attribute(.unique) var carId: Int
    var name: String?
    var vin: String?
    var model: String?
    var trimBadging: String?
    var marketingName: String?
    var exteriorColor: String?
    var efficiency: Double?
    var cachedAt: Date

    init(from car: Car) {
        self.carId = car.id
        self.name = car.name
        self.vin = car.vin
        self.model = car.model
        self.trimBadging = car.trimBadging
        self.marketingName = car.marketingName
        self.exteriorColor = car.exteriorColor
        self.efficiency = car.efficiency
        self.cachedAt = Date()
    }

    func toCar() -> Car {
        Car(
            id: carId,
            name: name,
            vin: vin,
            model: model,
            trimBadging: trimBadging,
            marketingName: marketingName,
            exteriorColor: exteriorColor,
            wheelType: nil,
            spoilerType: nil,
            efficiency: efficiency,
            settings: nil
        )
    }
}
