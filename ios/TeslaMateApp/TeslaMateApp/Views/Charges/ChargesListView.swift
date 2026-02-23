import SwiftUI

struct ChargesListView: View {
    let carId: Int
    @State private var viewModel = ChargesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.charges.isEmpty && viewModel.isLoading {
                    ProgressView("Loading charges...")
                } else if viewModel.charges.isEmpty {
                    ContentUnavailableView(
                        "No Charges",
                        systemImage: "bolt.fill",
                        description: Text("Charging data will appear here once available.")
                    )
                } else {
                    List {
                        ForEach(viewModel.charges) { charge in
                            NavigationLink(destination: ChargeDetailView(chargeId: charge.id)) {
                                ChargeRowView(charge: charge)
                            }
                            .onAppear {
                                if charge.id == viewModel.charges.last?.id {
                                    Task { await viewModel.loadMore(carId: carId) }
                                }
                            }
                        }

                        if viewModel.isLoading && !viewModel.charges.isEmpty {
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
                await viewModel.loadCharges(carId: carId)
            }
            .navigationTitle("Charges")
            .task {
                if viewModel.charges.isEmpty {
                    await viewModel.loadCharges(carId: carId)
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
