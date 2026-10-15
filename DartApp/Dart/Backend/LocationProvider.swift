import CoreLocation
import Foundation

/// One-shot, when-in-use location for ranking nearby requests. Nothing is stored or sent anywhere
/// except as the point the Earn feed is sorted around.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var current: GeoPoint?
    var onUpdate: ((GeoPoint) -> Void)?
    private var waiters: [CheckedContinuation<GeoPoint?, Never>] = []

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

    /// A fresh fix, or the last known one if none arrives within `timeout` (or access is denied).
    func freshFix(timeout: TimeInterval = 5) async -> GeoPoint? {
        switch manager.authorizationStatus {
        case .denied, .restricted: return current
        default: break
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            refresh()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resolveWaiters(with: self?.current)
            }
        }
    }

    private func resolveWaiters(with point: GeoPoint?) {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume(returning: point) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .notDetermined: break
            case .denied, .restricted: self.resolveWaiters(with: self.current)
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = GeoPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        Task { @MainActor in
            self.current = point
            self.onUpdate?(point)
            self.resolveWaiters(with: point)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolveWaiters(with: self.current) }
    }
}

extension GeoPoint {
    /// Straight-line distance in meters.
    func distance(to other: GeoPoint) -> Double {
        CLLocation(latitude: lat, longitude: lng).distance(from: CLLocation(latitude: other.lat, longitude: other.lng))
    }
}
