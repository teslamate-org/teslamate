import SwiftUI

struct DrivesListView: View {
    let carId: Int
    @State private var viewModel = DrivesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.drives.isEmpty && viewModel.isLoading {
                    ProgressView("Loading drives...")
                } else if viewModel.drives.isEmpty {
                    ContentUnavailableView(
                        "No Drives",
                        systemImage: "road.lanes",
                        description: Text("Drive data will appear here once available.")
                    )
                } else {
                    List {
                        ForEach(viewModel.drives) { drive in
                            NavigationLink(destination: DriveDetailView(driveId: drive.id)) {
                                DriveRowView(drive: drive)
                            }
                            .onAppear {
                                if drive.id == viewModel.drives.last?.id {
                                    Task { await viewModel.loadMore(carId: carId) }
                                }
                            }
                        }

                        if viewModel.isLoading && !viewModel.drives.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.loadDrives(carId: carId)
            }
            .navigationTitle("Drives")
            .task {
                if viewModel.drives.isEmpty {
                    await viewModel.loadDrives(carId: carId)
                }
            }
            .overlay {
                if let error = viewModel.error {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.cornerRadius(8))
                            .padding()
                    }
                }
            }
        }
    }
}
