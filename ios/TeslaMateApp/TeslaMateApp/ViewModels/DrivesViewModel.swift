import Foundation

@Observable
class DrivesViewModel {
    var drives: [Drive] = []
    var isLoading = false
    var error: String?
    var hasMore = true

    private var currentPage = 1
    private let perPage = 20

    func loadDrives(carId: Int) async {
        guard !isLoading else { return }

        isLoading = true
        currentPage = 1
        error = nil

        do {
            let response = try await APIClient.shared.getDrives(carId: carId, page: 1, perPage: perPage)
            await MainActor.run {
                self.drives = response.data
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
            let response = try await APIClient.shared.getDrives(carId: carId, page: currentPage, perPage: perPage)
            await MainActor.run {
                self.drives.append(contentsOf: response.data)
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
