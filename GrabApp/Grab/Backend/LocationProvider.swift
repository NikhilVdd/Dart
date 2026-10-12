import CoreLocation
import Foundation

/// One-shot, when-in-use location for ranking nearby requests. Nothing is stored or sent anywhere
/// except as the point the Earn feed is sorted around.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var current: GeoPoint?
    var onUpdate: ((GeoPoint) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Asks for permission the first time, then fetches a fresh fix.
    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: break
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status != .notDetermined, status != .denied, status != .restricted { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = GeoPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        Task { @MainActor in
            self.current = point
            self.onUpdate?(point)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension GeoPoint {
    /// Straight-line distance in meters.
    func distance(to other: GeoPoint) -> Double {
        CLLocation(latitude: lat, longitude: lng).distance(from: CLLocation(latitude: other.lat, longitude: other.lng))
    }
}
