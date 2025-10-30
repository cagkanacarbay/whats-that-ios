import Foundation

public struct GeoCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LocationSampleSource: String, Codable, Equatable, Sendable {
    case live
    case exif
    case manual
}

public struct DiscoveryLocationSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let coordinate: GeoCoordinate
    public let timestamp: Date
    public let horizontalAccuracy: Double
    public let source: LocationSampleSource

    public init(
        id: UUID = UUID(),
        coordinate: GeoCoordinate,
        timestamp: Date,
        horizontalAccuracy: Double,
        source: LocationSampleSource
    ) {
        self.id = id
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }
}

public struct NearbyPlace: Codable, Equatable, Sendable, Identifiable {
    public struct LocalizedText: Codable, Equatable, Sendable {
        public let text: String
        public let languageCode: String?

        public init(text: String, languageCode: String? = nil) {
            self.text = text
            self.languageCode = languageCode
        }
    }

    public struct PlaceLocation: Codable, Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public let id: String
    public let name: String?
    public let displayName: LocalizedText?
    public let formattedAddress: String?
    public let adrFormatAddress: String?
    public let googleMapsUri: String?
    public let primaryType: String?
    public let primaryTypeDisplayName: LocalizedText?
    public let types: [String]?
    public let location: PlaceLocation?
    public let subDestinations: [NearbyPlace]?

    public init(
        id: String,
        name: String? = nil,
        displayName: LocalizedText? = nil,
        formattedAddress: String? = nil,
        adrFormatAddress: String? = nil,
        googleMapsUri: String? = nil,
        primaryType: String? = nil,
        primaryTypeDisplayName: LocalizedText? = nil,
        types: [String]? = nil,
        location: PlaceLocation? = nil,
        subDestinations: [NearbyPlace]? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.formattedAddress = formattedAddress
        self.adrFormatAddress = adrFormatAddress
        self.googleMapsUri = googleMapsUri
        self.primaryType = primaryType
        self.primaryTypeDisplayName = primaryTypeDisplayName
        self.types = types
        self.location = location
        self.subDestinations = subDestinations
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case formattedAddress
        case adrFormatAddress
        case googleMapsUri
        case primaryType
        case primaryTypeDisplayName
        case types
        case location
        case subDestinations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let displayName = try container.decodeIfPresent(LocalizedText.self, forKey: .displayName)
        let formattedAddress = try container.decodeIfPresent(String.self, forKey: .formattedAddress)
        let adrFormatAddress = try container.decodeIfPresent(String.self, forKey: .adrFormatAddress)
        let googleMapsUri = try container.decodeIfPresent(String.self, forKey: .googleMapsUri)
        let primaryType = try container.decodeIfPresent(String.self, forKey: .primaryType)
        let primaryTypeDisplayName = try container.decodeIfPresent(LocalizedText.self, forKey: .primaryTypeDisplayName)
        let types = try container.decodeIfPresent([String].self, forKey: .types)
        let location = try container.decodeIfPresent(PlaceLocation.self, forKey: .location)
        let subDestinations = try container.decodeIfPresent([NearbyPlace].self, forKey: .subDestinations)

        let fallbackIdentifier = decodedId
            ?? name
            ?? googleMapsUri
            ?? "\(location?.latitude ?? 0)-\(location?.longitude ?? 0)"
        self.id = fallbackIdentifier
        self.name = name
        self.displayName = displayName
        self.formattedAddress = formattedAddress
        self.adrFormatAddress = adrFormatAddress
        self.googleMapsUri = googleMapsUri
        self.primaryType = primaryType
        self.primaryTypeDisplayName = primaryTypeDisplayName
        self.types = types
        self.location = location
        self.subDestinations = subDestinations
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(formattedAddress, forKey: .formattedAddress)
        try container.encodeIfPresent(adrFormatAddress, forKey: .adrFormatAddress)
        try container.encodeIfPresent(googleMapsUri, forKey: .googleMapsUri)
        try container.encodeIfPresent(primaryType, forKey: .primaryType)
        try container.encodeIfPresent(primaryTypeDisplayName, forKey: .primaryTypeDisplayName)
        try container.encodeIfPresent(types, forKey: .types)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(subDestinations, forKey: .subDestinations)
    }
}

public struct NearbyPlacesSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let centroid: GeoCoordinate
    public let origin: GeoCoordinate
    public let radiusMeters: Double
    public let fetchedAt: Date
    public let places: [NearbyPlace]
    public let sourceSampleId: UUID

    public init(
        id: UUID = UUID(),
        centroid: GeoCoordinate,
        origin: GeoCoordinate,
        radiusMeters: Double,
        fetchedAt: Date,
        places: [NearbyPlace],
        sourceSampleId: UUID
    ) {
        self.id = id
        self.centroid = centroid
        self.origin = origin
        self.radiusMeters = radiusMeters
        self.fetchedAt = fetchedAt
        self.places = places
        self.sourceSampleId = sourceSampleId
    }
}

public struct NearbyPlacesContext: Codable, Equatable, Sendable {
    public let snapshotId: UUID
    public let distanceMeters: Double
    public let horizontalAccuracyMeters: Double
    public let distanceUncertaintyMeters: Double
    public let summary: String

    public init(
        snapshotId: UUID,
        distanceMeters: Double,
        horizontalAccuracyMeters: Double,
        distanceUncertaintyMeters: Double,
        summary: String
    ) {
        self.snapshotId = snapshotId
        self.distanceMeters = distanceMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.distanceUncertaintyMeters = distanceUncertaintyMeters
        self.summary = summary
    }
}

public struct NearbyPlacesSelection: Codable, Equatable, Sendable {
    public let snapshot: NearbyPlacesSnapshot
    public let context: NearbyPlacesContext

    public init(snapshot: NearbyPlacesSnapshot, context: NearbyPlacesContext) {
        self.snapshot = snapshot
        self.context = context
    }
}

public extension GeoCoordinate {
    func distance(to other: GeoCoordinate) -> Double {
        let earthRadius = 6_371_000.0

        let lat1 = latitude.radians
        let lon1 = longitude.radians
        let lat2 = other.latitude.radians
        let lon2 = other.longitude.radians

        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
}
