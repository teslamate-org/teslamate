import SwiftUI
import MapKit

struct DriveMapView: View {
    let positions: [Position]

    private var coordinates: [CLLocationCoordinate2D] {
        positions.compactMap { $0.coordinate }
    }

    private var region: MapCameraPosition {
        guard let first = coordinates.first else {
            return .automatic
        }

        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (lats.max()! - lats.min()!) * 1.3 + 0.005,
            longitudeDelta: (lons.max()! - lons.min()!) * 1.3 + 0.005
        )

        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        Map(initialPosition: region) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 3)
            }

            if let start = coordinates.first {
                Annotation("Start", coordinate: start) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            if let end = coordinates.last, coordinates.count > 1 {
                Annotation("End", coordinate: end) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            }
        }
        .mapStyle(.standard)
    }
}
