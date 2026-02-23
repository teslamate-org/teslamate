import XCTest
@testable import TeslaMateApp

final class VehicleSummaryTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeFullSummary() throws {
        let json = """
        {
            "display_name": "My Tesla",
            "state": "online",
            "since": "2024-01-15T10:30:00Z",
            "healthy": true,
            "latitude": 37.7749,
            "longitude": -122.4194,
            "heading": 180,
            "battery_level": 75,
            "usable_battery_level": 73,
            "charging_state": "Disconnected",
            "ideal_battery_range_km": 350.5,
            "est_battery_range_km": 320.0,
            "rated_battery_range_km": 340.2,
            "charge_energy_added": 15.5,
            "charge_limit_soc": 90,
            "charge_port_door_open": false,
            "charger_actual_current": 0,
            "charger_phases": null,
            "charger_power": 0,
            "charger_voltage": 0,
            "charge_current_request": null,
            "charge_current_request_max": null,
            "time_to_full_charge": 0.0,
            "scheduled_charging_start_time": null,
            "speed": null,
            "power": -1,
            "shift_state": null,
            "outside_temp": 18.5,
            "inside_temp": 22.3,
            "is_climate_on": false,
            "is_preconditioning": false,
            "climate_keeper_mode": "off",
            "odometer": 45123.7,
            "locked": true,
            "sentry_mode": false,
            "plugged_in": false,
            "windows_open": false,
            "doors_open": false,
            "trunk_open": false,
            "frunk_open": false,
            "is_user_present": false,
            "elevation": 15,
            "geofence": "Home",
            "model": "3",
            "trim_badging": "P",
            "exterior_color": "Red",
            "wheel_type": "Stiletto20",
            "spoiler_type": "Passive",
            "version": "2024.2.7",
            "update_available": false,
            "update_version": null,
            "tpms_pressure_fl": 2.9,
            "tpms_pressure_fr": 2.9,
            "tpms_pressure_rl": 3.0,
            "tpms_pressure_rr": 3.0,
            "active_route_destination": null,
            "active_route_latitude": null,
            "active_route_longitude": null,
            "active_route_energy_at_arrival": null,
            "active_route_miles_to_arrival": null,
            "active_route_minutes_to_arrival": null,
            "center_display_state": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(VehicleSummary.self, from: json)

        XCTAssertEqual(summary.displayName, "My Tesla")
        XCTAssertEqual(summary.state, "online")
        XCTAssertEqual(summary.healthy, true)
        XCTAssertEqual(summary.latitude!, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(summary.longitude!, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(summary.batteryLevel, 75)
        XCTAssertEqual(summary.ratedBatteryRangeKm!, 340.2, accuracy: 0.1)
        XCTAssertEqual(summary.locked, true)
        XCTAssertEqual(summary.sentryMode, false)
        XCTAssertEqual(summary.geofence, "Home")
        XCTAssertEqual(summary.version, "2024.2.7")
    }

    func testDecodeMinimalSummary() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let summary = try decoder.decode(VehicleSummary.self, from: json)

        XCTAssertNil(summary.displayName)
        XCTAssertNil(summary.state)
        XCTAssertNil(summary.batteryLevel)
        XCTAssertNil(summary.latitude)
    }

    // MARK: - Computed Properties

    func testFormattedStateCapitalizes() {
        let summary = makeSummary(state: "online")
        XCTAssertEqual(summary.formattedState, "Online")
    }

    func testFormattedStateUnknownWhenNil() {
        let summary = makeSummary(state: nil)
        XCTAssertEqual(summary.formattedState, "Unknown")
    }

    func testBatteryColorGreen() {
        let summary = makeSummary(batteryLevel: 80)
        XCTAssertEqual(summary.batteryColor, "green")
    }

    func testBatteryColorYellow() {
        let summary = makeSummary(batteryLevel: 35)
        XCTAssertEqual(summary.batteryColor, "yellow")
    }

    func testBatteryColorRed() {
        let summary = makeSummary(batteryLevel: 15)
        XCTAssertEqual(summary.batteryColor, "red")
    }

    func testBatteryColorGrayWhenNil() {
        let summary = makeSummary(batteryLevel: nil)
        XCTAssertEqual(summary.batteryColor, "gray")
    }

    func testBatteryColorBoundary51IsGreen() {
        XCTAssertEqual(makeSummary(batteryLevel: 51).batteryColor, "green")
    }

    func testBatteryColorBoundary50IsYellow() {
        XCTAssertEqual(makeSummary(batteryLevel: 50).batteryColor, "yellow")
    }

    func testBatteryColorBoundary21IsYellow() {
        XCTAssertEqual(makeSummary(batteryLevel: 21).batteryColor, "yellow")
    }

    func testBatteryColorBoundary20IsRed() {
        XCTAssertEqual(makeSummary(batteryLevel: 20).batteryColor, "red")
    }

    func testIsChargingTrue() {
        XCTAssertTrue(makeSummary(state: "charging").isCharging)
    }

    func testIsChargingFalse() {
        XCTAssertFalse(makeSummary(state: "online").isCharging)
    }

    func testIsDrivingTrue() {
        XCTAssertTrue(makeSummary(state: "driving").isDriving)
    }

    func testIsDrivingFalse() {
        XCTAssertFalse(makeSummary(state: "online").isDriving)
    }

    func testRangeKmPrefersRated() {
        let summary = VehicleSummary(
            displayName: nil, state: nil, since: nil, healthy: nil,
            latitude: nil, longitude: nil, heading: nil,
            batteryLevel: nil, usableBatteryLevel: nil, chargingState: nil,
            idealBatteryRangeKm: 300.0, estBatteryRangeKm: 280.0,
            ratedBatteryRangeKm: 340.0, chargeEnergyAdded: nil,
            chargeLimitSoc: nil, chargePortDoorOpen: nil,
            chargerActualCurrent: nil, chargerPhases: nil, chargerPower: nil,
            chargerVoltage: nil, chargeCurrentRequest: nil,
            chargeCurrentRequestMax: nil, timeToFullCharge: nil,
            scheduledChargingStartTime: nil, speed: nil, power: nil,
            shiftState: nil, outsideTemp: nil, insideTemp: nil,
            isClimateOn: nil, isPreconditioning: nil, climateKeeperMode: nil,
            odometer: nil, locked: nil, sentryMode: nil, pluggedIn: nil,
            windowsOpen: nil, doorsOpen: nil, trunkOpen: nil, frunkOpen: nil,
            isUserPresent: nil, elevation: nil, geofence: nil, model: nil,
            trimBadging: nil, exteriorColor: nil, wheelType: nil,
            spoilerType: nil, version: nil, updateAvailable: nil,
            updateVersion: nil, tpmsPressureFl: nil, tpmsPressureFr: nil,
            tpmsPressureRl: nil, tpmsPressureRr: nil,
            activeRouteDestination: nil, activeRouteLatitude: nil,
            activeRouteLongitude: nil, activeRouteEnergyAtArrival: nil,
            activeRouteMilesToArrival: nil, activeRouteMinutesToArrival: nil,
            centerDisplayState: nil
        )
        XCTAssertEqual(summary.rangeKm, 340.0)
    }

    func testRangeKmFallsBackToIdeal() {
        let summary = VehicleSummary(
            displayName: nil, state: nil, since: nil, healthy: nil,
            latitude: nil, longitude: nil, heading: nil,
            batteryLevel: nil, usableBatteryLevel: nil, chargingState: nil,
            idealBatteryRangeKm: 300.0, estBatteryRangeKm: 280.0,
            ratedBatteryRangeKm: nil, chargeEnergyAdded: nil,
            chargeLimitSoc: nil, chargePortDoorOpen: nil,
            chargerActualCurrent: nil, chargerPhases: nil, chargerPower: nil,
            chargerVoltage: nil, chargeCurrentRequest: nil,
            chargeCurrentRequestMax: nil, timeToFullCharge: nil,
            scheduledChargingStartTime: nil, speed: nil, power: nil,
            shiftState: nil, outsideTemp: nil, insideTemp: nil,
            isClimateOn: nil, isPreconditioning: nil, climateKeeperMode: nil,
            odometer: nil, locked: nil, sentryMode: nil, pluggedIn: nil,
            windowsOpen: nil, doorsOpen: nil, trunkOpen: nil, frunkOpen: nil,
            isUserPresent: nil, elevation: nil, geofence: nil, model: nil,
            trimBadging: nil, exteriorColor: nil, wheelType: nil,
            spoilerType: nil, version: nil, updateAvailable: nil,
            updateVersion: nil, tpmsPressureFl: nil, tpmsPressureFr: nil,
            tpmsPressureRl: nil, tpmsPressureRr: nil,
            activeRouteDestination: nil, activeRouteLatitude: nil,
            activeRouteLongitude: nil, activeRouteEnergyAtArrival: nil,
            activeRouteMilesToArrival: nil, activeRouteMinutesToArrival: nil,
            centerDisplayState: nil
        )
        XCTAssertEqual(summary.rangeKm, 300.0)
    }

    func testRangeKmNilWhenAllNil() {
        let summary = makeSummary()
        XCTAssertNil(summary.rangeKm)
    }

    // MARK: - Helpers

    private func makeSummary(state: String? = nil, batteryLevel: Int? = nil) -> VehicleSummary {
        VehicleSummary(
            displayName: nil, state: state, since: nil, healthy: nil,
            latitude: nil, longitude: nil, heading: nil,
            batteryLevel: batteryLevel, usableBatteryLevel: nil, chargingState: nil,
            idealBatteryRangeKm: nil, estBatteryRangeKm: nil,
            ratedBatteryRangeKm: nil, chargeEnergyAdded: nil,
            chargeLimitSoc: nil, chargePortDoorOpen: nil,
            chargerActualCurrent: nil, chargerPhases: nil, chargerPower: nil,
            chargerVoltage: nil, chargeCurrentRequest: nil,
            chargeCurrentRequestMax: nil, timeToFullCharge: nil,
            scheduledChargingStartTime: nil, speed: nil, power: nil,
            shiftState: nil, outsideTemp: nil, insideTemp: nil,
            isClimateOn: nil, isPreconditioning: nil, climateKeeperMode: nil,
            odometer: nil, locked: nil, sentryMode: nil, pluggedIn: nil,
            windowsOpen: nil, doorsOpen: nil, trunkOpen: nil, frunkOpen: nil,
            isUserPresent: nil, elevation: nil, geofence: nil, model: nil,
            trimBadging: nil, exteriorColor: nil, wheelType: nil,
            spoilerType: nil, version: nil, updateAvailable: nil,
            updateVersion: nil, tpmsPressureFl: nil, tpmsPressureFr: nil,
            tpmsPressureRl: nil, tpmsPressureRr: nil,
            activeRouteDestination: nil, activeRouteLatitude: nil,
            activeRouteLongitude: nil, activeRouteEnergyAtArrival: nil,
            activeRouteMilesToArrival: nil, activeRouteMinutesToArrival: nil,
            centerDisplayState: nil
        )
    }
}
