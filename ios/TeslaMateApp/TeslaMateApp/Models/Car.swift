import Foundation

struct Car: Codable, Identifiable {
    let id: Int
    let name: String?
    let vin: String?
    let model: String?
    let trimBadging: String?
    let marketingName: String?
    let exteriorColor: String?
    let wheelType: String?
    let spoilerType: String?
    let efficiency: Double?
    var settings: CarSettings?

    var displayName: String {
        name ?? marketingName ?? "Tesla"
    }
}

struct CarSettings: Codable {
    let suspendMin: Int?
    let suspendAfterIdleMin: Int?
    let reqNotUnlocked: Bool?
    let freeSupercharging: Bool?
    let useStreamingApi: Bool?
}
