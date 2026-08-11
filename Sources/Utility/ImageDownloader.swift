// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import AttributedCore
import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public final class ImageDownloader: Attributed.RemoteImageProvider, @unchecked Sendable {
    private let session: URLSession
    private let fileManager: FileManager
    private let cacheDirectory: URL
    private let enableDiskCache: Bool
    private let enableMemoryCache: Bool
    private let memoryCacheLock = NSLock()
    private var memoryCache: [URL: AttributedCore.PlatformImage] = [:]

    public init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil,
        enableDiskCache: Bool = true,
        enableMemoryCache: Bool = true
    ) {
        self.session = session
        self.fileManager = fileManager
        self.enableDiskCache = enableDiskCache
        self.enableMemoryCache = enableMemoryCache
        self.cacheDirectory = cacheDirectory
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "AttributedImageDownloader",
                isDirectory: true
            )
    }

    public func cachedImage(
        for url: URL
    ) throws -> AttributedCore.PlatformImage? {
        if enableMemoryCache, let image = memoryCachedImage(for: url) {
            return image
        }

        guard enableDiskCache else {
            return nil
        }

        let fileURL = cachedFileURL(for: url)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)

        guard let image = platformImage(from: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        if enableMemoryCache {
            storeInMemory(image, for: url)
        }
        return image
    }

    public func image(for url: URL) async throws -> AttributedCore.PlatformImage {
        if let image = try? cachedImage(for: url) {
            return image
        }

        let (data, response) = try await session.data(from: url)

        guard
            let response = response as? HTTPURLResponse,
            200..<300 ~= response.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        guard let image = platformImage(from: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        if enableDiskCache {
            try? fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try? data.write(to: cachedFileURL(for: url), options: .atomic)
        }

        if enableMemoryCache {
            storeInMemory(image, for: url)
        }
        return image
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(key, isDirectory: false)
    }

    private func memoryCachedImage(
        for url: URL
    ) -> AttributedCore.PlatformImage? {
        memoryCacheLock.lock()
        defer { memoryCacheLock.unlock() }
        return memoryCache[url]
    }

    private func storeInMemory(
        _ image: AttributedCore.PlatformImage,
        for url: URL
    ) {
        memoryCacheLock.lock()
        memoryCache[url] = image
        memoryCacheLock.unlock()
    }

    private func platformImage(
        from data: Data
    ) -> AttributedCore.PlatformImage? {
        #if canImport(UIKit)
        UIImage(data: data)
        #elseif canImport(AppKit)
        NSImage(data: data)
        #endif
    }
}
