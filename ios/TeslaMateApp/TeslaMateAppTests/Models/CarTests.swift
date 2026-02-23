import XCTest
@testable import TeslaMateApp

final class CarTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeCar() throws {
        let json = """
        {
            "id": 1,
            "name": "My Tesla",
            "vin": "5YJ3E1EA1PF000001",
            "model": "3",
            "trim_badging": "P",
            "marketing_name": "Model 3 Performance",
            "exterior_color": "Red",
            "wheel_type": "Stiletto20",
            "spoiler_type": "Passive",
            "efficiency": 0.153
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let car = try decoder.decode(Car.self, from: json)

        XCTAssertEqual(car.id, 1)
        XCTAssertEqual(car.name, "My Tesla")
        XCTAssertEqual(car.vin, "5YJ3E1EA1PF000001")
        XCTAssertEqual(car.model, "3")
        XCTAssertEqual(car.trimBadging, "P")
        XCTAssertEqual(car.marketingName, "Model 3 Performance")
        XCTAssertEqual(car.exteriorColor, "Red")
        XCTAssertEqual(car.wheelType, "Stiletto20")
        XCTAssertEqual(car.spoilerType, "Passive")
        XCTAssertEqual(car.efficiency!, 0.153, accuracy: 0.001)
    }

    func testDecodeCarWithNulls() throws {
        let json = """
        {
            "id": 2,
            "name": null,
            "vin": null,
            "model": null,
            "trim_badging": null,
            "marketing_name": null,
            "exterior_color": null,
            "wheel_type": null,
            "spoiler_type": null,
            "efficiency": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let car = try decoder.decode(Car.self, from: json)

        XCTAssertEqual(car.id, 2)
        XCTAssertNil(car.name)
        XCTAssertNil(car.vin)
        XCTAssertNil(car.model)
        XCTAssertNil(car.efficiency)
    }

    func testDecodeCarWithSettings() throws {
        let json = """
        {
            "id": 1,
            "name": "My Tesla",
            "settings": {
                "suspend_min": 21,
                "suspend_after_idle_min": 15,
                "req_not_unlocked": true,
                "free_supercharging": false,
                "use_streaming_api": true
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let car = try decoder.decode(Car.self, from: json)

        XCTAssertNotNil(car.settings)
        XCTAssertEqual(car.settings?.suspendMin, 21)
        XCTAssertEqual(car.settings?.suspendAfterIdleMin, 15)
        XCTAssertEqual(car.settings?.reqNotUnlocked, true)
        XCTAssertEqual(car.settings?.freeSupercharging, false)
        XCTAssertEqual(car.settings?.useStreamingApi, true)
    }

    // MARK: - Computed Properties

    func testDisplayNameUsesName() {
        let car = Car(id: 1, name: "Custom Name", vin: nil, model: nil, trimBadging: nil, marketingName: "Model S", exteriorColor: nil, wheelType: nil, spoilerType: nil, efficiency: nil)
        XCTAssertEqual(car.displayName, "Custom Name")
    }

    func testDisplayNameFallsBackToMarketingName() {
        let car = Car(id: 1, name: nil, vin: nil, model: nil, trimBadging: nil, marketingName: "Model 3 LR", exteriorColor: nil, wheelType: nil, spoilerType: nil, efficiency: nil)
        XCTAssertEqual(car.displayName, "Model 3 LR")
    }

    func testDisplayNameFallsBackToTesla() {
        let car = Car(id: 1, name: nil, vin: nil, model: nil, trimBadging: nil, marketingName: nil, exteriorColor: nil, wheelType: nil, spoilerType: nil, efficiency: nil)
        XCTAssertEqual(car.displayName, "Tesla")
    }

    // MARK: - Encoding

    func testCarRoundTrip() throws {
        let car = Car(id: 5, name: "Test", vin: "VIN123", model: "Y", trimBadging: nil, marketingName: nil, exteriorColor: "Blue", wheelType: nil, spoilerType: nil, efficiency: 0.16)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(car)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Car.self, from: data)

        XCTAssertEqual(decoded.id, car.id)
        XCTAssertEqual(decoded.name, car.name)
        XCTAssertEqual(decoded.vin, car.vin)
        XCTAssertEqual(decoded.exteriorColor, car.exteriorColor)
    }
}
