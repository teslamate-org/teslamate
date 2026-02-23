import Foundation
import SwiftData

@Model
class CachedVehicleSummary {
    @Attribute(.unique) var carId: Int
    var jsonData: Data
    var cachedAt: Date

    init(carId: Int, summary: VehicleSummary) throws {
        self.carId = carId
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.jsonData = try encoder.encode(summary)
        self.cachedAt = Date()
    }

    func toSummary() throws -> VehicleSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VehicleSummary.self, from: jsonData)
    }
}
