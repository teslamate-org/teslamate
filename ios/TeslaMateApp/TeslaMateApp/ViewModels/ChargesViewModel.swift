import Foundation

@Observable
class ChargesViewModel {
    var charges: [ChargingSession] = []
    var isLoading = false
    var error: String?
    var hasMore = true

    private var currentPage = 1
    private let perPage = 20

    func loadCharges(carId: Int) async {
        guard !isLoading else { return }

        isLoading = true
        currentPage = 1
        error = nil

        do {
            let response = try await APIClient.shared.getCharges(carId: carId, page: 1, perPage: perPage)
            await MainActor.run {
                self.charges = response.data
                self.hasMore = response.data.count >= self.perPage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func loadMore(carId: Int) async {
        guard !isLoading, hasMore else { return }

        isLoading = true
        currentPage += 1

        do {
            let response = try await APIClient.shared.getCharges(carId: carId, page: currentPage, perPage: perPage)
            await MainActor.run {
                self.charges.append(contentsOf: response.data)
                self.hasMore = response.data.count >= self.perPage
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.currentPage -= 1
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
