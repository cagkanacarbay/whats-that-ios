#if canImport(UIKit)
import UIKit
import WhatsThatDomain

public enum ImageEncodingError: Error {
    case invalidImage
}

public final class DefaultDiscoveryImageEncoder: DiscoveryImageEncodingService {
    public init() {}

    public func encodeImageData(_ media: DiscoveryCapturedMedia, maxDimension: Int) async throws -> Data {
        guard let image = UIImage(data: media.data) else {
            throw ImageEncodingError.invalidImage
        }

        let resized = await resize(image: image, maxDimension: CGFloat(maxDimension))
        guard let data = resized.jpegData(compressionQuality: 0.9) else {
            throw ImageEncodingError.invalidImage
        }
        return data
    }

    public func makeBase64Payload(from media: DiscoveryCapturedMedia, maxDimension: Int) async throws -> String {
        let data = try await encodeImageData(media, maxDimension: maxDimension)
        return data.base64EncodedString()
    }

    private func resize(image: UIImage, maxDimension: CGFloat) async -> UIImage {
        let size = image.size
        let maxCurrentDimension = max(size.width, size.height)
        guard maxCurrentDimension > maxDimension else {
            return image
        }

        let scale = maxDimension / maxCurrentDimension
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
                continuation.resume(returning: resizedImage)
            }
        }
    }
}
#endif
