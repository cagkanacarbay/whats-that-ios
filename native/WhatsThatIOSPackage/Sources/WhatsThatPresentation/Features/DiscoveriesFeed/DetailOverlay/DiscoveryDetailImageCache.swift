import Foundation
import UIKit
import UIKit

final class DiscoveryDetailImageCache {
    static let shared = DiscoveryDetailImageCache()

    private let cache = NSCache<NSNumber, DiscoveryPlatformImage>()
    private let lock = NSLock()

    private init() {}

    func store(_ image: DiscoveryPlatformImage, for discoveryId: Int64) {
        lock.lock()
        cache.setObject(image, forKey: NSNumber(value: discoveryId))
        lock.unlock()
    }

    func image(for discoveryId: Int64) -> DiscoveryPlatformImage? {
        lock.lock()
        let image = cache.object(forKey: NSNumber(value: discoveryId))
        lock.unlock()
        return image
    }
}
