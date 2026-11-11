import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct LocationStep: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition
    @State private var displayedRadius: Double
    @State private var visibleCenter: CLLocationCoordinate2D?
    @State private var locationMessage: String?
    @State private var showsSettingsLink = false

    init(viewModel: ProfileCreationViewModel, locationService: LocationService) {
        self.viewModel = viewModel
        self.locationService = locationService
        let radius = Double(viewModel.state.searchRadiusKilometers)
        _displayedRadius = State(initialValue: radius)
        _camera = State(initialValue: viewModel.state.location.map {
            .region(Self.region(around: $0.coordinate, radiusKilometers: radius))
        } ?? .automatic)
    }

    private var location: SelectedLocation? { viewModel.state.location }

    var body: some View {
        VStack(spacing: 14) {
            mapCard

            ZStack {
                if location != nil {
                    radiusControl
                        .transition(.onboardingReveal(reduceMotion: reduceMotion))
                } else {
                    Text(locationMessage ?? "Tap anywhere on the map to drop your pin.")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .transition(.opacity)
                }
            }
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: location == nil)
        }
        .frame(maxWidth: OnboardingTheme.contentWidth)
        .task { await showUsersCountryIfNeeded() }
        .task(id: location) { await resolvePlaceName() }
        .onChange(of: viewModel.state.searchRadiusKilometers) { old, new in
            // Slider drags arrive in small steps and are applied directly;
            // larger jumps (taps, keyboard, VoiceOver) glide.
            let animation: Animation? = reduceMotion || abs(new - old) <= 3 ? nil : .smooth(duration: 0.55)
            withAnimation(animation) {
                displayedRadius = Double(new)
                if let location {
                    camera = .region(Self.region(around: location.coordinate, radiusKilometers: Double(new)))
                }
            }
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        RadiusMap(
            radiusKilometers: displayedRadius,
            center: location?.coordinate,
            camera: $camera,
            onTap: { select($0, source: .map) },
            onCameraSettled: { visibleCenter = $0 }
        )
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            if let location {
                placeLabel(location)
                    .padding(.top, 12)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }
        }
        .overlay(alignment: .bottom) {
            useLocationButton
                .padding(.bottom, 12)
        }
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: location?.placeName)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map")
        .accessibilityAction(named: "Drop pin at the centre of the map") {
            if let visibleCenter { select(visibleCenter, source: .map) }
        }
    }

    private func placeLabel(_ location: SelectedLocation) -> some View {
        Label(location.placeName ?? "Pinned location", systemImage: "mappin.and.ellipse")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .padding(.horizontal, 16)
            .accessibilityLabel("Selected place: \(location.placeName ?? "pinned location")")
    }

    private var useLocationButton: some View {
        HStack(spacing: 8) {
            Button(action: requestDeviceLocation) {
                HStack(spacing: 8) {
                    if locationService.isRequestingLocation {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: location?.source == .device ? "location.fill" : "location")
                    }
                    Text("Use my location")
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(OnboardingTheme.accentGradient.opacity(0.8), lineWidth: 1) }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(locationService.isRequestingLocation)

            if showsSettingsLink, let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Settings")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityHint("Opens Settings to allow location access.")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showsSettingsLink)
    }

    // MARK: - Radius

    private var radiusControl: some View {
        let radius = viewModel.state.searchRadiusKilometers
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Search radius")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                Spacer()
                Text("\(radius)")
                    .font(.system(.title2, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .contentTransition(.numericText(value: Double(radius)))
                    .animation(.snappy(duration: 0.2), value: radius)
                Text("km")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .accessibilityHidden(true)

            GlowSlider(
                value: Binding(
                    get: { viewModel.state.searchRadiusKilometers },
                    set: { viewModel.updateSearchRadius($0) }
                ),
                scale: SliderScale(bounds: SearchRadiusRules.range, exponent: 1.8),
                label: "Search radius",
                valueDescription: { "\($0) kilometers" }
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .onboardingSurface(cornerRadius: 24)
    }

    // MARK: - Actions

    private func select(_ coordinate: CLLocationCoordinate2D, source: SelectedLocation.Source) {
        viewModel.selectLocation(coordinate, source: source)
        locationMessage = nil
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) {
            camera = .region(Self.region(around: coordinate, radiusKilometers: displayedRadius))
        }
    }

    /// Permission is only requested here, after an explicit tap.
    private func requestDeviceLocation() {
        Task {
            do {
                let current = try await locationService.requestCurrentLocation()
                showsSettingsLink = false
                select(current.coordinate, source: .device)
            } catch LocationServiceError.requestAlreadyInProgress {
                return
            } catch LocationServiceError.permissionDenied, LocationServiceError.servicesDisabled {
                showsSettingsLink = true
                locationMessage = "Location access is off. Tap the map to choose a place instead."
                announce(locationMessage)
            } catch {
                locationMessage = "We couldn’t find your location. Tap the map to choose a place instead."
                announce(locationMessage)
            }
        }
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    /// Opens on the user's country, derived from their region setting rather
    /// than their position, so no permission is needed.
    private func showUsersCountryIfNeeded() async {
        guard location == nil,
              let regionCode = Locale.current.region?.identifier,
              let country = Locale(identifier: "en_US").localizedString(forRegionCode: regionCode),
              let request = MKGeocodingRequest(addressString: country),
              let item = try? await request.mapItems.first,
              location == nil else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) {
            camera = .region(MKCoordinateRegion(center: item.location.coordinate, latitudinalMeters: 900_000, longitudinalMeters: 900_000))
        }
    }

    private func resolvePlaceName() async {
        guard let location, location.placeName == nil else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled,
              let request = MKReverseGeocodingRequest(location: CLLocation(latitude: location.latitude, longitude: location.longitude)),
              let item = try? await request.mapItems.first,
              !Task.isCancelled else { return }
        let name = item.addressRepresentations?.cityWithContext ?? item.name
        viewModel.updatePlaceName(name, for: location.coordinate)
    }

    /// The circle takes a growing share of the map as the radius grows, so
    /// both the circle and the map scale visibly while adjusting.
    static func region(around center: CLLocationCoordinate2D, radiusKilometers: Double) -> MKCoordinateRegion {
        let radius = max(radiusKilometers, 0.5)
        let share = 0.5 + 0.25 * log(max(radius, 1)) / log(Double(SearchRadiusRules.range.upperBound))
        let span = max(2 * radius * 1000 / share, 3_000)
        return MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
    }
}

/// Interpolating `radiusKilometers` animates only the circle overlay; the
/// underlying map view keeps its identity.
private struct RadiusMap: View, Animatable {
    var radiusKilometers: Double
    let center: CLLocationCoordinate2D?
    @Binding var camera: MapCameraPosition
    let onTap: (CLLocationCoordinate2D) -> Void
    let onCameraSettled: (CLLocationCoordinate2D) -> Void

    var animatableData: Double {
        get { radiusKilometers }
        set { radiusKilometers = newValue }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                if let center {
                    MapCircle(center: center, radius: radiusKilometers * 1000)
                        .foregroundStyle(OnboardingTheme.blue.opacity(0.18))
                        .stroke(OnboardingTheme.cyan.opacity(0.9), lineWidth: 1.5)

                    Annotation("Selected location", coordinate: center, anchor: .center) {
                        LocationPin()
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {}
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    onTap(coordinate)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                onCameraSettled(context.region.center)
            }
        }
    }
}

private struct LocationPin: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var hasLanded = false

    var body: some View {
        ZStack {
            Circle()
                .fill(OnboardingTheme.cyan.opacity(0.35))
                .frame(width: 44, height: 44)
                .scaleEffect(isPulsing ? 1.7 : 0.7)
                .opacity(isPulsing ? 0 : 0.9)
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .overlay { Circle().strokeBorder(OnboardingTheme.accentGradient, lineWidth: 4) }
                .shadow(color: OnboardingTheme.cyan.opacity(0.9), radius: 10)
        }
        .scaleEffect(hasLanded ? 1 : 0.2)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.45)) { hasLanded = true }
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.9).repeatForever(autoreverses: false)) { isPulsing = true }
        }
        .accessibilityHidden(true)
    }
}
