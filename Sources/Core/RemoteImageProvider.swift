// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation

public extension Attributed {
protocol RemoteImageProvider: Sendable {
    func cachedImage(for url: URL) throws -> PlatformImage?
    func image(for url: URL) async throws -> PlatformImage
}

enum RemoteImageEnvironment {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedProvider: (any RemoteImageProvider)?

    public static var provider: (any RemoteImageProvider)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedProvider
        }
        set {
            lock.lock()
            storedProvider = newValue
            lock.unlock()
        }
    }

    public static func cachedImage(for url: URL) throws -> PlatformImage? {
        try requiredProvider().cachedImage(for: url)
    }

    public static func image(for url: URL) async throws -> PlatformImage {
        try await requiredProvider().image(for: url)
    }

    private static func requiredProvider() -> any RemoteImageProvider {
        guard let provider else {
            preconditionFailure(
                "Remote images require a RemoteImageProvider. Set ARemoteImageEnvironment.provider before loading remote images."
            )
        }

        return provider
    }
}
}

public extension Attributed.RemoteImageProvider {
    func cachedImage(for url: URL) throws -> PlatformImage? {
        nil
    }
}
