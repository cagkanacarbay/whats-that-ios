import Foundation

public protocol DiscoveryImageEncodingService: Sendable {
    func encodeImageData(_ media: DiscoveryCapturedMedia, maxDimension: Int) async throws -> Data
    func makeBase64Payload(from media: DiscoveryCapturedMedia, maxDimension: Int) async throws -> String
}
