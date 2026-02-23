import XCTest
@testable import TeslaMateApp

final class APITypesTests: XCTestCase {

    // MARK: - AuthResponse

    func testDecodeAuthResponse() throws {
        let json = """
        {
            "jwt": "eyJhbGciOiJIUzI1NiJ9.test.signature",
            "expires_at": 1705363200
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.jwt, "eyJhbGciOiJIUzI1NiJ9.test.signature")
        XCTAssertEqual(response.expiresAt, 1705363200)
    }

    // MARK: - AuthRequest

    func testEncodeAuthRequest() throws {
        let request = AuthRequest(token: "my_api_token")

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["token"] as? String, "my_api_token")
    }

    // MARK: - APIErrorResponse

    func testDecodeAPIError() throws {
        let json = """
        {"error": "Invalid API token"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(APIErrorResponse.self, from: json)
        XCTAssertEqual(response.error, "Invalid API token")
    }

    // MARK: - PaginatedResponse

    func testDecodePaginatedResponse() throws {
        let json = """
        {
            "data": [{"id": 1, "distance": 25.3}, {"id": 2, "distance": 10.1}],
            "page": 1,
            "per_page": 20,
            "total": 42
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(PaginatedResponse<SimpleDrive>.self, from: json)

        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.page, 1)
        XCTAssertEqual(response.perPage, 20)
        XCTAssertEqual(response.total, 42)
    }

    // MARK: - DataResponse

    func testDecodeDataResponse() throws {
        let json = """
        {
            "data": {"id": 1, "distance": 25.3}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DataResponse<SimpleDrive>.self, from: json)

        XCTAssertEqual(response.data.id, 1)
        XCTAssertEqual(response.data.distance!, 25.3, accuracy: 0.1)
    }

    // MARK: - HealthResponse

    func testDecodeHealthResponse() throws {
        let json = """
        {"status": "ok", "version": "1.31.0"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(HealthResponse.self, from: json)
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.version, "1.31.0")
    }
}

// Helper type for testing generic responses
private struct SimpleDrive: Codable {
    let id: Int
    let distance: Double?
}
