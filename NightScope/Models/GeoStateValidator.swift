import CoreLocation
import MapKit

enum GeoStateValidator {
    private enum Constants {
        static let defaultCoordinate = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
        static let maximumLatitude = 89.999_999
        static let minimumLatitudeDelta = 0.000_5
        static let minimumLongitudeDelta = 0.000_5
        static let maximumLatitudeDelta = 180.0
        static let maximumLongitudeDelta = 360.0
    }

    static var defaultCoordinate: CLLocationCoordinate2D {
        Constants.defaultCoordinate
    }

    static func sanitizedCoordinate(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        guard let coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              abs(coordinate.latitude) <= 90,
              abs(coordinate.longitude) <= 180 else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: max(-Constants.maximumLatitude, min(coordinate.latitude, Constants.maximumLatitude)),
            longitude: normalizedLongitude(coordinate.longitude)
        )
    }

    static func sanitizedSpan(_ span: MKCoordinateSpan?) -> MKCoordinateSpan? {
        guard let span,
              span.latitudeDelta.isFinite,
              span.longitudeDelta.isFinite else {
            return nil
        }

        let latitudeDelta = max(
            Constants.minimumLatitudeDelta,
            min(abs(span.latitudeDelta), Constants.maximumLatitudeDelta)
        )
        let longitudeDelta = max(
            Constants.minimumLongitudeDelta,
            min(abs(span.longitudeDelta), Constants.maximumLongitudeDelta)
        )

        return MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }

    static func sanitizedRegion(
        center: CLLocationCoordinate2D,
        span: MKCoordinateSpan,
        fallbackCenter: CLLocationCoordinate2D? = nil
    ) -> MKCoordinateRegion? {
        guard let sanitizedSpan = sanitizedSpan(span) else {
            return nil
        }

        let sanitizedCenter = sanitizedCoordinate(center)
            ?? sanitizedCoordinate(fallbackCenter)
            ?? defaultCoordinate

        return MKCoordinateRegion(center: sanitizedCenter, span: sanitizedSpan)
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 {
            normalized -= 360
        } else if normalized <= -180 {
            normalized += 360
        }
        return normalized
    }
}
