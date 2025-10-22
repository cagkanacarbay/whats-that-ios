import Foundation
import SwiftUI
import WhatsThatShared

#if canImport(UIKit)
import UIKit
public typealias DiscoveryPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias DiscoveryPlatformImage = NSImage
#endif

@MainActor
public final class DiscoveryImageLoader: ObservableObject {
    @Published public private(set) var image: DiscoveryPlatformImage?
    @Published public private(set) var isLoading = false
    @Published public private(set) var didFail = false

    public let discoveryId: Int64

    private let cache: DiscoveryAssetCache
    private let session: URLSession
    private var remoteURL: URL?

    public init(
        discoveryId: Int64,
        remoteURL: URL?,
        cache: DiscoveryAssetCache = .shared,
        session: URLSession = .shared
    ) {
        self.discoveryId = discoveryId
        self.remoteURL = remoteURL
        self.cache = cache
        self.session = session
    }

    public func updateRemoteURL(_ url: URL?) {
        guard remoteURL != url else { return }
        remoteURL = url
        image = nil
        didFail = false
    }

    public func loadIfNeeded(force: Bool = false) {
        guard force || (image == nil && !isLoading) else { return }

        isLoading = true

        Task { [weak self] in
            guard let self else { return }
            await self.loadImage(force: force)
        }
    }

    public func reload() {
        updateRemoteURL(remoteURL)
        loadIfNeeded(force: true)
    }

    public func cachedFileURL() async -> URL? {
        await cache.cachedImageURL(for: discoveryId)
    }

    public func ensureImageCached() async -> URL? {
        if let existing = await cache.cachedImageURL(for: discoveryId) {
            return existing
        }

        guard let remoteURL else { return nil }
        return await cache.ensureImageCached(
            for: discoveryId,
            signedURL: remoteURL,
            session: session
        )
    }

    private func loadImage(force: Bool) async {
        defer { isLoading = false }

        if !force, let cached = await loadCachedImage() {
            image = cached
            return
        }

        guard let remoteURL else {
            didFail = true
            return
        }

        _ = await cache.ensureImageCached(
            for: discoveryId,
            signedURL: remoteURL,
            session: session
        )

        if let cached = await loadCachedImage() {
            image = cached
            return
        }

        didFail = true
    }

    private func loadCachedImage() async -> DiscoveryPlatformImage? {
        guard let fileURL = await cache.cachedImageURL(for: discoveryId) else {
            return nil
        }

        do {
            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            }.value
            return DiscoveryPlatformImage(data: data)
        } catch {
            return nil
        }
    }
}

public enum DiscoveryImageLoadPhase {
    case empty
    case loading
    case success(DiscoveryPlatformImage)
    case failure
}

public struct DiscoveryCachedImage<Content: View>: View {
    private let content: (DiscoveryImageLoadPhase) -> Content
    private let remoteURL: URL?

    @StateObject private var loader: DiscoveryImageLoader

    public init(
        discoveryId: Int64,
        remoteURL: URL?,
        cache: DiscoveryAssetCache = .shared,
        session: URLSession = .shared,
        @ViewBuilder content: @escaping (DiscoveryImageLoadPhase) -> Content
    ) {
        self.content = content
        self.remoteURL = remoteURL
        _loader = StateObject(
            wrappedValue: DiscoveryImageLoader(
                discoveryId: discoveryId,
                remoteURL: remoteURL,
                cache: cache,
                session: session
            )
        )
    }

    public var body: some View {
        content(currentPhase)
            .onAppear {
                loader.updateRemoteURL(remoteURL)
                loader.loadIfNeeded()
            }
            .onChange(of: remoteURL) { newValue in
                loader.updateRemoteURL(newValue)
                loader.loadIfNeeded()
            }
    }

    private var currentPhase: DiscoveryImageLoadPhase {
        if let image = loader.image {
            return .success(image)
        }

        if loader.didFail {
            return .failure
        }

        return loader.isLoading ? .loading : .empty
    }
}
