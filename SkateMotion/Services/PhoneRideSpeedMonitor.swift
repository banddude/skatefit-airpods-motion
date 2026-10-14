import CoreLocation
import Foundation
import SwiftUI

/// Optional outdoor context, sampled from the IPHONE, not the skateboard.
/// We intentionally do not store, export, or upload coordinates or a route.
@MainActor
final class PhoneRideSpeedMonitor: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var tracking = false
    @Published private(set) var status = "GPS off"
    @Published private(set) var speedMetersPerSecond: Double?
    @Published private(set) var horizontalAccuracyMeters: Double?
    @Published private(set) var speedAccuracyMetersPerSecond: Double?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = "Location Services disabled"
            return
        }
        tracking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for optional iPhone location permission"
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            status = "Waiting for outdoor GPS speed"
        case .denied, .restricted:
            tracking = false
            status = "Location denied. Enable While Using App in iOS Settings."
        @unknown default:
            tracking = false
            status = "Location authorization unavailable"
        }
    }

    func stop() {
        tracking = false
        manager.stopUpdatingLocation()
        status = "GPS off"
        speedMetersPerSecond = nil
        speedAccuracyMetersPerSecond = nil
        horizontalAccuracyMeters = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard tracking else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied ||
                  manager.authorizationStatus == .restricted {
            stop()
            status = "Location permission denied"
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard tracking, let location = locations.last else { return }
        let age = abs(location.timestamp.timeIntervalSinceNow)
        let horizontal = location.horizontalAccuracy
        let accuracy = location.speedAccuracy
        guard age <= 5, horizontal > 0, horizontal <= 25,
              location.speed >= 0, location.speed.isFinite,
              accuracy >= 0, accuracy <= 2.5 else {
            speedMetersPerSecond = nil
            status = "GPS too imprecise. Try outdoors with open sky."
            return
        }
        speedMetersPerSecond = location.speed
        horizontalAccuracyMeters = horizontal
        speedAccuracyMetersPerSecond = accuracy
        status = "iPhone outdoor travel speed (not skateboard position)"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        speedMetersPerSecond = nil
        status = "GPS unavailable: \(error.localizedDescription)"
    }

    var milesPerHour: Double? { speedMetersPerSecond.map { $0 * 2.2369362921 } }
}
