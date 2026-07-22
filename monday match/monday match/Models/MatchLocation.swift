import Foundation
import CoreLocation

struct MatchLocation: Equatable, Codable {
    var latitude: Double
    var longitude: Double
    var coarseLatitude: Double
    var coarseLongitude: Double
    var radiusKilometers: Int
    var updatedAt: Date

    init(
        coordinate: CLLocationCoordinate2D,
        radiusKilometers: Int,
        updatedAt: Date = Date()
    ) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        coarseLatitude = Self.roundCoordinate(coordinate.latitude)
        coarseLongitude = Self.roundCoordinate(coordinate.longitude)
        self.radiusKilometers = radiusKilometers
        self.updatedAt = updatedAt
    }

    private static func roundCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
