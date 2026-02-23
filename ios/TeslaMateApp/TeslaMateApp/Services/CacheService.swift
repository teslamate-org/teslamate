import Foundation
import SwiftData

@MainActor
class CacheService {
    static let shared = CacheService()

    private var container: ModelContainer?

    func configure() throws {
        let schema = Schema([
            CachedCar.self,
            CachedDrive.self,
            CachedChargingSession.self,
            CachedVehicleSummary.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Cars

    func cacheCars(_ cars: [Car]) throws {
        guard let container else { return }
        let context = container.mainContext

        for car in cars {
            let cached = CachedCar(from: car)
            context.insert(cached)
        }
        try context.save()
    }

    func getCachedCars() throws -> [Car] {
        guard let container else { return [] }
        let context = container.mainContext
        let descriptor = FetchDescriptor<CachedCar>()
        return try context.fetch(descriptor).map { $0.toCar() }
    }

    // MARK: - Summary

    func cacheSummary(carId: Int, summary: VehicleSummary) throws {
        guard let container else { return }
        let context = container.mainContext

        let descriptor = FetchDescriptor<CachedVehicleSummary>(
            predicate: #Predicate { $0.carId == carId }
        )

        if let existing = try context.fetch(descriptor).first {
            context.delete(existing)
        }

        let cached = try CachedVehicleSummary(carId: carId, summary: summary)
        context.insert(cached)
        try context.save()
    }

    func getCachedSummary(carId: Int) throws -> VehicleSummary? {
        guard let container else { return nil }
        let context = container.mainContext

        let ttl: TimeInterval = 5 * 60
        let cutoff = Date().addingTimeInterval(-ttl)

        let descriptor = FetchDescriptor<CachedVehicleSummary>(
            predicate: #Predicate { $0.carId == carId && $0.cachedAt > cutoff }
        )

        return try context.fetch(descriptor).first?.toSummary()
    }
}
