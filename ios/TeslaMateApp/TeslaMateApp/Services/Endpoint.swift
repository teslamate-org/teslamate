import Foundation

enum Endpoint {
    case login
    case health
    case cars
    case car(id: Int)
    case carSummary(carId: Int)
    case drives(carId: Int, page: Int, perPage: Int)
    case drive(id: Int)
    case driveGpx(id: Int)
    case charges(carId: Int, page: Int, perPage: Int)
    case charge(id: Int)
    case positions(carId: Int, page: Int, perPage: Int)

    var path: String {
        switch self {
        case .login:
            return "/api/v1/auth/login"
        case .health:
            return "/api/v1/health"
        case .cars:
            return "/api/v1/cars"
        case .car(let id):
            return "/api/v1/cars/\(id)"
        case .carSummary(let carId):
            return "/api/v1/cars/\(carId)/summary"
        case .drives(let carId, let page, let perPage):
            return "/api/v1/cars/\(carId)/drives?page=\(page)&per_page=\(perPage)"
        case .drive(let id):
            return "/api/v1/drives/\(id)"
        case .driveGpx(let id):
            return "/api/v1/drives/\(id)/gpx"
        case .charges(let carId, let page, let perPage):
            return "/api/v1/cars/\(carId)/charges?page=\(page)&per_page=\(perPage)"
        case .charge(let id):
            return "/api/v1/charges/\(id)"
        case .positions(let carId, let page, let perPage):
            return "/api/v1/cars/\(carId)/positions?page=\(page)&per_page=\(perPage)"
        }
    }

    var method: String {
        switch self {
        case .login:
            return "POST"
        default:
            return "GET"
        }
    }

    func url(baseURL: String) -> URL? {
        URL(string: baseURL + path)
    }
}
