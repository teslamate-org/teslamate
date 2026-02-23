import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return message
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func request<T: Decodable>(_ endpoint: Endpoint, body: Encodable? = nil) async throws -> T {
        let auth = AuthService.shared
        let serverURL = await auth.serverURL

        guard !serverURL.isEmpty, let url = endpoint.url(baseURL: serverURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method

        if let jwt = await auth.jwt {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            // Try refreshing the token
            _ = try await auth.login()
            // Retry the request once
            if let jwt = await auth.jwt {
                var retryRequest = request
                retryRequest.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await session.data(for: retryRequest)
                guard let retryHTTP = retryResponse as? HTTPURLResponse, retryHTTP.statusCode == 200 else {
                    throw APIError.notAuthenticated
                }
                return try decoder.decode(T.self, from: retryData)
            }
            throw APIError.notAuthenticated
        default:
            if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.error)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Convenience Methods

    func getCars() async throws -> [Car] {
        let response: DataResponse<[Car]> = try await request(.cars)
        return response.data
    }

    func getCar(id: Int) async throws -> Car {
        let response: DataResponse<Car> = try await request(.car(id: id))
        return response.data
    }

    func getCarSummary(carId: Int) async throws -> VehicleSummary {
        let response: DataResponse<VehicleSummary> = try await request(.carSummary(carId: carId))
        return response.data
    }

    func getDrives(carId: Int, page: Int = 1, perPage: Int = 20) async throws -> PaginatedResponse<Drive> {
        try await request(.drives(carId: carId, page: page, perPage: perPage))
    }

    func getDrive(id: Int) async throws -> Drive {
        let response: DataResponse<Drive> = try await request(.drive(id: id))
        return response.data
    }

    func getDriveWithPositions(id: Int) async throws -> DriveWithPositions {
        let response: DataResponse<DriveWithPositions> = try await request(.driveGpx(id: id))
        return response.data
    }

    func getCharges(carId: Int, page: Int = 1, perPage: Int = 20) async throws -> PaginatedResponse<ChargingSession> {
        try await request(.charges(carId: carId, page: page, perPage: perPage))
    }

    func getChargeDetail(id: Int) async throws -> ChargeDetailResponse {
        let response: DataResponse<ChargeDetailResponse> = try await request(.charge(id: id))
        return response.data
    }
}

struct DriveWithPositions: Codable {
    let drive: Drive
    let positions: [Position]
}

struct ChargeDetailResponse: Codable {
    let chargingProcess: ChargingSession
    let charges: [ChargeDataPoint]
}
