import AppKit

/// LRU-ish cache of decoded cover images, keyed by file path.
final class CoverCache {
    static let shared = CoverCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 50
    }

    func image(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func setImage(_ image: NSImage, for path: String) {
        cache.setObject(image, forKey: path as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
