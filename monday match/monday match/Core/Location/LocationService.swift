import Combine
import CoreLocation
import Foundation

enum LocationServiceError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable
    case requestAlreadyInProgress

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location services are disabled on this device."
        case .permissionDenied:
            return "Location permission was not granted."
        case .locationUnavailable:
            return "Your location could not be determined."
        case .requestAlreadyInProgress:
            return "A location request is already running."
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingLocation = false

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    /// True while we are waiting for the user to answer the permission prompt.
    /// The actual location request is started once permission has been granted.
    private var isAwaitingAuthorization = false

    override init() {
        super.init()

        // `self` (and therefore `manager`) may only be touched after `super.init()`.
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        // A previous request is still running; do not overwrite its continuation.
        guard locationContinuation == nil else {
            throw LocationServiceError.requestAlreadyInProgress
        }

        let status = manager.authorizationStatus

        switch status {
        case .denied, .restricted:
            throw LocationServiceError.permissionDenied

        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            break

        @unknown default:
            throw LocationServiceError.permissionDenied
        }

        isRequestingLocation = true

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation

            if status == .notDetermined {
                // Wait for the permission answer first. Calling `requestLocation()`
                // here would fail immediately because there is no authorization yet.
                isAwaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(with result: Result<CLLocation, Error>) {
        isRequestingLocation = false
        isAwaitingAuthorization = false

        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            authorizationStatus = status

            // Only react when we are actually waiting for the permission answer.
            guard isAwaitingAuthorization else { return }

            switch status {
            case .denied, .restricted:
                finish(with: .failure(LocationServiceError.permissionDenied))

            case .authorizedAlways, .authorizedWhenInUse:
                isAwaitingAuthorization = false
                manager.requestLocation()

            case .notDetermined:
                break

            @unknown default:
                finish(with: .failure(LocationServiceError.permissionDenied))
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
