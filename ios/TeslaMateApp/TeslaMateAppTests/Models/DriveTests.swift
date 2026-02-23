import XCTest
@testable import TeslaMateApp

final class DriveTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeDriveWithAddresses() throws {
        let json = """
        {
            "id": 42,
            "car_id": 1,
            "start_date": "2024-01-15T08:00:00Z",
            "end_date": "2024-01-15T08:45:00Z",
            "start_address": {
                "id": 10,
                "display_name": "123 Home St",
                "city": "San Francisco",
                "county": "SF County",
                "country": "US",
                "state": "CA",
                "road": "Home St",
                "house_number": "123"
            },
            "end_address": {
                "id": 11,
                "display_name": "456 Work Ave",
                "city": "San Francisco",
                "county": "SF County",
                "country": "US",
                "state": "CA",
                "road": "Work Ave",
                "house_number": "456"
            },
            "start_geofence": {
                "id": 1,
                "name": "Home"
            },
            "end_geofence": {
                "id": 2,
                "name": "Office"
            },
            "distance": 25.3,
            "duration_min": 45,
            "speed_max": 110,
            "power_max": 150,
            "power_min": -60,
            "start_km": 45000.0,
            "end_km": 45025.3,
            "start_ideal_range_km": 350.0,
            "end_ideal_range_km": 310.0,
            "start_rated_range_km": 340.0,
            "end_rated_range_km": 300.0,
            "outside_temp_avg": 18.5,
            "inside_temp_avg": 22.0,
            "ascent": 120,
            "descent": 80
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let drive = try decoder.decode(Drive.self, from: json)

        XCTAssertEqual(drive.id, 42)
        XCTAssertEqual(drive.carId, 1)
        XCTAssertEqual(drive.distance!, 25.3, accuracy: 0.1)
        XCTAssertEqual(drive.durationMin, 45)
        XCTAssertEqual(drive.speedMax, 110)
        XCTAssertEqual(drive.startAddress?.displayName, "123 Home St")
        XCTAssertEqual(drive.endAddress?.city, "San Francisco")
        XCTAssertEqual(drive.startGeofence?.name, "Home")
        XCTAssertEqual(drive.endGeofence?.name, "Office")
        XCTAssertEqual(drive.startRatedRangeKm!, 340.0, accuracy: 0.1)
        XCTAssertEqual(drive.endRatedRangeKm!, 300.0, accuracy: 0.1)
    }

    func testDecodeMinimalDrive() throws {
        let json = """
        {
            "id": 1,
            "distance": null,
            "duration_min": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let drive = try decoder.decode(Drive.self, from: json)

        XCTAssertEqual(drive.id, 1)
        XCTAssertNil(drive.distance)
        XCTAssertNil(drive.durationMin)
        XCTAssertNil(drive.startAddress)
        XCTAssertNil(drive.endAddress)
    }

    // MARK: - Computed Properties

    func testStartDisplayNameUsesGeofence() {
        let drive = makeDrive(
            startGeofence: GeofenceInfo(id: 1, name: "Home"),
            startAddress: AddressInfo(id: 1, displayName: "123 St", city: nil, county: nil, country: nil, state: nil, road: nil, houseNumber: nil)
        )
        XCTAssertEqual(drive.startDisplayName, "Home")
    }

    func testStartDisplayNameFallsBackToAddress() {
        let drive = makeDrive(
            startGeofence: nil,
            startAddress: AddressInfo(id: 1, displayName: "123 Main St", city: nil, county: nil, country: nil, state: nil, road: nil, houseNumber: nil)
        )
        XCTAssertEqual(drive.startDisplayName, "123 Main St")
    }

    func testStartDisplayNameFallsBackToUnknown() {
        let drive = makeDrive(startGeofence: nil, startAddress: nil)
        XCTAssertEqual(drive.startDisplayName, "Unknown")
    }

    func testEndDisplayNameUsesGeofence() {
        let drive = makeDrive(endGeofence: GeofenceInfo(id: 2, name: "Office"))
        XCTAssertEqual(drive.endDisplayName, "Office")
    }

    func testFormattedDistanceWithValue() {
        let drive = makeDrive(distance: 42.567)
        XCTAssertEqual(drive.formattedDistance, "42.6 km")
    }

    func testFormattedDistanceWhenNil() {
        let drive = makeDrive(distance: nil)
        XCTAssertEqual(drive.formattedDistance, "--")
    }

    func testFormattedDurationWithHoursAndMinutes() {
        let drive = makeDrive(durationMin: 125)
        XCTAssertEqual(drive.formattedDuration, "2h 5m")
    }

    func testFormattedDurationMinutesOnly() {
        let drive = makeDrive(durationMin: 45)
        XCTAssertEqual(drive.formattedDuration, "45m")
    }

    func testFormattedDurationWhenNil() {
        let drive = makeDrive(durationMin: nil)
        XCTAssertEqual(drive.formattedDuration, "--")
    }

    func testRangeUsed() {
        let drive = makeDrive(startRatedRangeKm: 340.0, endRatedRangeKm: 300.0)
        XCTAssertEqual(drive.rangeUsed!, 40.0, accuracy: 0.1)
    }

    func testRangeUsedNilWhenMissing() {
        let drive = makeDrive(startRatedRangeKm: 340.0, endRatedRangeKm: nil)
        XCTAssertNil(drive.rangeUsed)
    }

    // MARK: - Helpers

    private func makeDrive(
        distance: Double? = nil,
        durationMin: Int? = nil,
        startGeofence: GeofenceInfo? = nil,
        startAddress: AddressInfo? = nil,
        endGeofence: GeofenceInfo? = nil,
        endAddress: AddressInfo? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil
    ) -> Drive {
        Drive(
            id: 1, carId: 1,
            startDate: nil, endDate: nil,
            startAddress: startAddress, endAddress: endAddress,
            startGeofence: startGeofence, endGeofence: endGeofence,
            distance: distance, durationMin: durationMin,
            speedMax: nil, powerMax: nil, powerMin: nil,
            startKm: nil, endKm: nil,
            startIdealRangeKm: nil, endIdealRangeKm: nil,
            startRatedRangeKm: startRatedRangeKm, endRatedRangeKm: endRatedRangeKm,
            outsideTempAvg: nil, insideTempAvg: nil,
            ascent: nil, descent: nil
        )
    }
}
