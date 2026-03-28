import SwiftUI
import MapKit

// MARK: - NSViewRepresentable wrapper for MKMapView

struct MapKitViewRepresentable: NSViewRepresentable {
    let pinCoordinate: CLLocationCoordinate2D?
    let centerTrigger: Int
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        // Metal レイヤーがサイズ0で初期化されるのを防ぐため、初期リージョン設定を遅延させる
        if let coord = pinCoordinate {
            DispatchQueue.main.async {
                mapView.setRegion(
                    MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)),
                    animated: false
                )
            }
        }
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(click)
        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        let prevTrigger = context.coordinator.lastCenterTrigger
        context.coordinator.parent = self
        context.coordinator.lastCenterTrigger = centerTrigger

        let existing = nsView.annotations.compactMap { $0 as? MKPointAnnotation }.first

        guard let newCoord = pinCoordinate else {
            if existing != nil { nsView.removeAnnotations(nsView.annotations) }
            return
        }

        if let existing {
            let coordChanged = existing.coordinate.latitude != newCoord.latitude ||
                               existing.coordinate.longitude != newCoord.longitude
            if coordChanged {
                existing.coordinate = newCoord
            }
            if coordChanged || prevTrigger != centerTrigger {
                let region = MKCoordinateRegion(center: newCoord, span: nsView.region.span)
                DispatchQueue.main.async {
                    nsView.setRegion(region, animated: true)
                }
            }
        } else {
            let ann = MKPointAnnotation()
            ann.coordinate = newCoord
            nsView.addAnnotation(ann)
            let region = MKCoordinateRegion(center: newCoord, span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0))
            DispatchQueue.main.async {
                nsView.setRegion(region, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitViewRepresentable
        var lastCenterTrigger: Int

        init(_ parent: MapKitViewRepresentable) {
            self.parent = parent
            self.lastCenterTrigger = parent.centerTrigger
        }

        @objc func handleTap(_ gr: NSClickGestureRecognizer) {
            guard let mapView = gr.view as? MKMapView else { return }
            let point = gr.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coord)
        }
    }
}

// MARK: - EquatableMapSection
// MapLocationPicker を Equatable でラップし、座標・isLocating が変わらない限り再描画しない

struct EquatableMapSection: View, Equatable {
    let coordinate: CLLocationCoordinate2D
    let onSelect: (CLLocationCoordinate2D) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    var body: some View {
        MapLocationPicker(
            selectedCoordinate: coordinate,
            onSelect: onSelect
        )
        .equatable()
    }
}

// MARK: - MapLocationPicker view

struct MapLocationPicker: View, Equatable {
    let selectedCoordinate: CLLocationCoordinate2D
    let onSelect: (CLLocationCoordinate2D) -> Void

    @State private var centerTrigger = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedCoordinate.latitude == rhs.selectedCoordinate.latitude &&
        lhs.selectedCoordinate.longitude == rhs.selectedCoordinate.longitude
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MapKitViewRepresentable(
                pinCoordinate: selectedCoordinate,
                centerTrigger: centerTrigger,
                onTap: { coord in onSelect(coord) }
            )
            .frame(height: 200)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            Text("地図をクリックして場所を選択")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
