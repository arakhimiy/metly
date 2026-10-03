import CoreLocation
import MapKit
import Observation

/// A reverse-geocoded place for "Where You Met".
public struct PlaceSuggestion: Equatable, Sendable {
    public var place: String
    public var city: String

    public init(place: String, city: String) {
        self.place = place
        self.city = city
    }
}

/// Fills "Where You Met" from the current location (When In Use, requested in context — PLAN Q16).
/// Creating it is cheap; nothing touches Core Location until you call a method.
@Observable
public final class LocationContextProvider {
    public enum Status: Equatable, Sendable {
        case idle
        case locating
        case resolved(PlaceSuggestion)
        case denied
        case failed
    }

    public private(set) var status: Status = .idle
    public private(set) var authorization: CLAuthorizationStatus = .notDetermined

    @ObservationIgnored private var manager: CLLocationManager?

    public init() {}

    public var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    public var isDenied: Bool { authorization == .denied || authorization == .restricted }
    public var needsPermission: Bool { authorization == .notDetermined }
    public var isLocating: Bool { status == .locating }

    /// Reads the current authorization without prompting.
    public func refreshAuthorization() {
        let manager = manager ?? CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
    }

    /// Requests When-In-Use access if needed (system prompt), then finds and reverse-geocodes the current place.
    /// Returns nil when denied, unavailable or timed out (~12 s; 60 s while the permission prompt may be up).
    @discardableResult
    public func resolveCurrentPlace() async -> PlaceSuggestion? {
        refreshAuthorization()
        guard !isDenied else {
            status = .denied
            return nil
        }
        status = .locating
        // Leave time for the system prompt on first use.
        let timeout: Duration = needsPermission ? .seconds(60) : .seconds(12)
        // A service session asks for When-In-Use authorization (iOS 18) and keeps it while we locate.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }

        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { await Self.locate() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .failed
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }
        refreshAuthorization()

        switch outcome {
        case .located(let location):
            if let suggestion = await Self.placeSuggestion(for: location) {
                status = .resolved(suggestion)
                return suggestion
            }
            status = .failed
        case .denied:
            status = .denied
        case .failed:
            status = .failed
        }
        return nil
    }

    // MARK: Private

    private enum Outcome: Sendable {
        case located(CLLocation)
        case denied
        case failed
    }

    nonisolated private static func locate() async -> Outcome {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    return .denied
                }
                if let location = update.location {
                    return .located(location)
                }
            }
        } catch {
            return .failed
        }
        return .failed
    }

    private static func placeSuggestion(for location: CLLocation) async -> PlaceSuggestion? {
        if #available(iOS 26, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return nil }
            let city = item.addressRepresentations?.cityName ?? ""
            let place = item.name ?? item.address?.shortAddress ?? ""
            return place.isEmpty && city.isEmpty ? nil : PlaceSuggestion(place: place, city: city)
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            let place = placemark.areasOfInterest?.first ?? placemark.name ?? ""
            let city = placemark.locality ?? ""
            return place.isEmpty && city.isEmpty ? nil : PlaceSuggestion(place: place, city: city)
        }
    }
}
