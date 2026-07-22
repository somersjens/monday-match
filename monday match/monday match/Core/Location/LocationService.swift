import CoreLocation
import Foundation

enum LocationServiceError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location services are disabled on this device."
        case .permissionDenied:
            return "Location permission was not granted."
        case .locationUnavailable:
            return "Your location could not be determined."
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRequestingLocation = false

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            throw LocationServiceError.permissionDenied

        case .authorizedAlways, .authorizedWhenInUse:
            break

        @unknown default:
            throw LocationServiceError.permissionDenied
        }

        isRequestingLocation = true

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        isRequestingLocation = false
        locationContinuation?.resume(with: result)
        locationContinuation = nil
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if manager.authorizationStatus == .denied ||
                manager.authorizationStatus == .restricted {
                finish(with: .failure(LocationServiceError.permissionDenied))
            } else if manager.authorizationStatus == .authorizedAlways ||
                        manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard let location = locations.last else {
                finish(with: .failure(LocationServiceError.locationUnavailable))
                return
            }

            finish(with: .success(location))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            finish(with: .failure(error))
        }
    }
}
