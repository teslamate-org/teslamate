import XCTest
@testable import TeslaMateApp

final class EndpointTests: XCTestCase {

    private let baseURL = "https://teslamate.example.com"

    // MARK: - Paths

    func testLoginPath() {
        XCTAssertEqual(Endpoint.login.path, "/api/v1/auth/login")
    }

    func testHealthPath() {
        XCTAssertEqual(Endpoint.health.path, "/api/v1/health")
    }

    func testCarsPath() {
        XCTAssertEqual(Endpoint.cars.path, "/api/v1/cars")
    }

    func testCarPath() {
        XCTAssertEqual(Endpoint.car(id: 5).path, "/api/v1/cars/5")
    }

    func testCarSummaryPath() {
        XCTAssertEqual(Endpoint.carSummary(carId: 3).path, "/api/v1/cars/3/summary")
    }

    func testDrivesPath() {
        XCTAssertEqual(
            Endpoint.drives(carId: 1, page: 2, perPage: 10).path,
            "/api/v1/cars/1/drives?page=2&per_page=10"
        )
    }

    func testDrivePath() {
        XCTAssertEqual(Endpoint.drive(id: 42).path, "/api/v1/drives/42")
    }

    func testDriveGpxPath() {
        XCTAssertEqual(Endpoint.driveGpx(id: 42).path, "/api/v1/drives/42/gpx")
    }

    func testChargesPath() {
        XCTAssertEqual(
            Endpoint.charges(carId: 1, page: 1, perPage: 20).path,
            "/api/v1/cars/1/charges?page=1&per_page=20"
        )
    }

    func testChargePath() {
        XCTAssertEqual(Endpoint.charge(id: 7).path, "/api/v1/charges/7")
    }

    func testPositionsPath() {
        XCTAssertEqual(
            Endpoint.positions(carId: 2, page: 1, perPage: 100).path,
            "/api/v1/cars/2/positions?page=1&per_page=100"
        )
    }

    // MARK: - Methods

    func testLoginMethodIsPost() {
        XCTAssertEqual(Endpoint.login.method, "POST")
    }

    func testHealthMethodIsGet() {
        XCTAssertEqual(Endpoint.health.method, "GET")
    }

    func testCarsMethodIsGet() {
        XCTAssertEqual(Endpoint.cars.method, "GET")
    }

    func testCarMethodIsGet() {
        XCTAssertEqual(Endpoint.car(id: 1).method, "GET")
    }

    func testCarSummaryMethodIsGet() {
        XCTAssertEqual(Endpoint.carSummary(carId: 1).method, "GET")
    }

    func testDrivesMethodIsGet() {
        XCTAssertEqual(Endpoint.drives(carId: 1, page: 1, perPage: 20).method, "GET")
    }

    func testChargesMethodIsGet() {
        XCTAssertEqual(Endpoint.charges(carId: 1, page: 1, perPage: 20).method, "GET")
    }

    func testPositionsMethodIsGet() {
        XCTAssertEqual(Endpoint.positions(carId: 1, page: 1, perPage: 100).method, "GET")
    }

    // MARK: - URL Construction

    func testLoginURL() {
        let url = Endpoint.login.url(baseURL: baseURL)
        XCTAssertEqual(url?.absoluteString, "https://teslamate.example.com/api/v1/auth/login")
    }

    func testCarsURL() {
        let url = Endpoint.cars.url(baseURL: baseURL)
        XCTAssertEqual(url?.absoluteString, "https://teslamate.example.com/api/v1/cars")
    }

    func testDrivesURLWithPagination() {
        let url = Endpoint.drives(carId: 1, page: 3, perPage: 15).url(baseURL: baseURL)
        XCTAssertEqual(
            url?.absoluteString,
            "https://teslamate.example.com/api/v1/cars/1/drives?page=3&per_page=15"
        )
    }

    func testChargesURLWithPagination() {
        let url = Endpoint.charges(carId: 2, page: 1, perPage: 20).url(baseURL: baseURL)
        XCTAssertEqual(
            url?.absoluteString,
            "https://teslamate.example.com/api/v1/cars/2/charges?page=1&per_page=20"
        )
    }

    func testURLWithEmptyBaseURL() {
        let url = Endpoint.health.url(baseURL: "")
        XCTAssertEqual(url?.absoluteString, "/api/v1/health")
    }
}
