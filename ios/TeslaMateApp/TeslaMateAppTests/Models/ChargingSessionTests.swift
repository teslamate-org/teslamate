import XCTest
@testable import TeslaMateApp

final class ChargingSessionTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeChargingSession() throws {
        let json = """
        {
            "id": 10,
            "car_id": 1,
            "start_date": "2024-01-15T22:00:00Z",
            "end_date": "2024-01-16T06:00:00Z",
            "address": {
                "id": 5,
                "display_name": "Home Charger",
                "city": "San Francisco",
                "county": null,
                "country": "US",
                "state": "CA",
                "road": null,
                "house_number": null
            },
            "geofence": {
                "id": 1,
                "name": "Home"
            },
            "charge_energy_added": 45.2,
            "charge_energy_used": 48.5,
            "start_ideal_range_km": 100.0,
            "end_ideal_range_km": 350.0,
            "start_rated_range_km": 95.0,
            "end_rated_range_km": 340.0,
            "start_battery_level": 20,
            "end_battery_level": 90,
            "duration_min": 480,
            "outside_temp_avg": 12.5,
            "cost": 8.50
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try decoder.decode(ChargingSession.self, from: json)

        XCTAssertEqual(session.id, 10)
        XCTAssertEqual(session.carId, 1)
        XCTAssertEqual(session.chargeEnergyAdded!, 45.2, accuracy: 0.1)
        XCTAssertEqual(session.startBatteryLevel, 20)
        XCTAssertEqual(session.endBatteryLevel, 90)
        XCTAssertEqual(session.durationMin, 480)
        XCTAssertEqual(session.cost!, 8.50, accuracy: 0.01)
        XCTAssertEqual(session.geofence?.name, "Home")
        XCTAssertEqual(session.address?.displayName, "Home Charger")
    }

    func testDecodeChargeDataPoint() throws {
        let json = """
        {
            "id": 100,
            "date": "2024-01-15T23:30:00Z",
            "battery_level": 55,
            "usable_battery_level": 54,
            "charge_energy_added": 12.3,
            "charger_actual_current": 32,
            "charger_phases": 3,
            "charger_pilot_current": 32,
            "charger_power": 11,
            "charger_voltage": 230,
            "ideal_battery_range_km": 220.0,
            "rated_battery_range_km": 210.0,
            "outside_temp": 12.0,
            "fast_charger_present": false,
            "fast_charger_brand": null,
            "fast_charger_type": null,
            "conn_charge_cable": "IEC"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let point = try decoder.decode(ChargeDataPoint.self, from: json)

        XCTAssertEqual(point.id, 100)
        XCTAssertEqual(point.batteryLevel, 55)
        XCTAssertEqual(point.chargerPower, 11)
        XCTAssertEqual(point.chargerVoltage, 230)
        XCTAssertEqual(point.fastChargerPresent, false)
        XCTAssertEqual(point.connChargeCable, "IEC")
    }

    // MARK: - Computed Properties

    func testLocationNameUsesGeofence() {
        let session = makeSession(
            geofence: GeofenceInfo(id: 1, name: "Home"),
            address: AddressInfo(id: 1, displayName: "123 St", city: nil, county: nil, country: nil, state: nil, road: nil, houseNumber: nil)
        )
        XCTAssertEqual(session.locationName, "Home")
    }

    func testLocationNameFallsBackToAddress() {
        let session = makeSession(
            geofence: nil,
            address: AddressInfo(id: 1, displayName: "123 Main St", city: nil, county: nil, country: nil, state: nil, road: nil, houseNumber: nil)
        )
        XCTAssertEqual(session.locationName, "123 Main St")
    }

    func testLocationNameFallsBackToUnknown() {
        let session = makeSession(geofence: nil, address: nil)
        XCTAssertEqual(session.locationName, "Unknown")
    }

    func testFormattedEnergy() {
        let session = makeSession(chargeEnergyAdded: 45.23)
        XCTAssertEqual(session.formattedEnergy, "45.2 kWh")
    }

    func testFormattedEnergyWhenNil() {
        let session = makeSession(chargeEnergyAdded: nil)
        XCTAssertEqual(session.formattedEnergy, "--")
    }

    func testFormattedDurationWithHours() {
        let session = makeSession(durationMin: 480)
        XCTAssertEqual(session.formattedDuration, "8h 0m")
    }

    func testFormattedDurationMinutesOnly() {
        let session = makeSession(durationMin: 30)
        XCTAssertEqual(session.formattedDuration, "30m")
    }

    func testFormattedDurationWhenNil() {
        let session = makeSession(durationMin: nil)
        XCTAssertEqual(session.formattedDuration, "--")
    }

    func testFormattedCost() {
        let session = makeSession(cost: 12.50)
        XCTAssertEqual(session.formattedCost, "$12.50")
    }

    func testFormattedCostWhenNil() {
        let session = makeSession(cost: nil)
        XCTAssertEqual(session.formattedCost, "--")
    }

    func testSocChange() {
        let session = makeSession(startBatteryLevel: 20, endBatteryLevel: 90)
        XCTAssertEqual(session.socChange, "20% → 90%")
    }

    func testSocChangeWhenNil() {
        let session = makeSession(startBatteryLevel: nil, endBatteryLevel: nil)
        XCTAssertEqual(session.socChange, "--")
    }

    func testChargeDataPointParsedDate() {
        let point = ChargeDataPoint(
            id: 1, date: "2024-01-15T23:30:00Z",
            batteryLevel: nil, usableBatteryLevel: nil, chargeEnergyAdded: nil,
            chargerActualCurrent: nil, chargerPhases: nil, chargerPilotCurrent: nil,
            chargerPower: nil, chargerVoltage: nil, idealBatteryRangeKm: nil,
            ratedBatteryRangeKm: nil, outsideTemp: nil, fastChargerPresent: nil,
            fastChargerBrand: nil, fastChargerType: nil, connChargeCable: nil
        )
        XCTAssertNotNil(point.parsedDate)
    }

    func testChargeDataPointParsedDateNilWhenNoDate() {
        let point = ChargeDataPoint(
            id: 1, date: nil,
            batteryLevel: nil, usableBatteryLevel: nil, chargeEnergyAdded: nil,
            chargerActualCurrent: nil, chargerPhases: nil, chargerPilotCurrent: nil,
            chargerPower: nil, chargerVoltage: nil, idealBatteryRangeKm: nil,
            ratedBatteryRangeKm: nil, outsideTemp: nil, fastChargerPresent: nil,
            fastChargerBrand: nil, fastChargerType: nil, connChargeCable: nil
        )
        XCTAssertNil(point.parsedDate)
    }

    // MARK: - Helpers

    private func makeSession(
        geofence: GeofenceInfo? = nil,
        address: AddressInfo? = nil,
        chargeEnergyAdded: Double? = nil,
        durationMin: Int? = nil,
        cost: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil
    ) -> ChargingSession {
        ChargingSession(
            id: 1, carId: 1,
            startDate: nil, endDate: nil,
            address: address, geofence: geofence,
            chargeEnergyAdded: chargeEnergyAdded, chargeEnergyUsed: nil,
            startIdealRangeKm: nil, endIdealRangeKm: nil,
            startRatedRangeKm: nil, endRatedRangeKm: nil,
            startBatteryLevel: startBatteryLevel, endBatteryLevel: endBatteryLevel,
            durationMin: durationMin, outsideTempAvg: nil, cost: cost
        )
    }
}
