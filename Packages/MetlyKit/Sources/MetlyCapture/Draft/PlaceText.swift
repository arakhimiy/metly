import Foundation
import MetlyCore

/// "Place, City" without naming the city twice.
///
/// Places reach a connection from several sources — typed "Hyatt Regency, Tashkent" next to an
/// auto-filled City, a reverse-geocoded short address that already ends in the city, older clients
/// that sent "place, city" as one string — and joining them naively shows
/// "Hyatt Regency, Tashkent, Tashkent". Every save and display path goes through these helpers.
public enum PlaceText {
    /// `place` without trailing ", {city}" components; nil when nothing is left or the place *is* the city.
    public static func normalizedPlace(_ place: String?, city: String?) -> String? {
        var place = (place ?? "").trimmed
        let city = (city ?? "").trimmed
        guard !place.isEmpty else { return nil }
        guard !city.isEmpty else { return place }
        if matches(place, city) { return nil }
        while let comma = place.lastIndex(of: ","), matches(String(place[place.index(after: comma)...]), city) {
            place = String(place[..<comma]).trimmed
        }
        return place.isEmpty ? nil : place
    }

    /// Display string: "Hyatt Regency, Tashkent" (place, then city once); nil when both are empty.
    public static func joined(place: String?, city: String?) -> String? {
        let city = (city ?? "").trimmed
        let parts = [normalizedPlace(place, city: city), city.isEmpty ? nil : city].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Display string for a meeting's place and city.
    public static func joined(_ context: MeetingContext) -> String? {
        joined(place: context.place, city: context.city)
    }

    /// `context` with its place de-duplicated against its city.
    public static func normalized(_ context: MeetingContext) -> MeetingContext {
        var context = context
        let city = (context.city ?? "").trimmed
        context.place = normalizedPlace(context.place, city: city)
        context.city = city.isEmpty ? nil : city
        return context
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmed.compare(rhs.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
