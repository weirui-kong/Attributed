// Copyright 2026 Kong Weirui
// SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import AttributedUtility

final class UtilityTests: XCTestCase {
    func testDownloaderCachesImageDataInTemporaryDirectory() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = URL(string: "https://example.com/image.png")!

        ImageURLProtocol.reset()

        let firstDownloader = ImageDownloader(
            session: session,
            cacheDirectory: cacheDirectory
        )
        _ = try await firstDownloader.image(for: url)

        let secondDownloader = ImageDownloader(
            session: session,
            cacheDirectory: cacheDirectory
        )
        let cachedImage = try secondDownloader.cachedImage(for: url)

        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(ImageURLProtocol.requestCount, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    func testDownloaderCanDisableDiskCache() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let downloader = ImageDownloader(
            session: URLSession(configuration: configuration),
            cacheDirectory: cacheDirectory,
            enableDiskCache: false
        )
        let url = URL(string: "https://example.com/memory-only.png")!

        ImageURLProtocol.reset()
        _ = try await downloader.image(for: url)
        _ = try await downloader.image(for: url)

        XCTAssertNotNil(try downloader.cachedImage(for: url))
        XCTAssertEqual(ImageURLProtocol.requestCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    }

    func testDownloaderCanDisableMemoryCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let downloader = ImageDownloader(
            session: URLSession(configuration: configuration),
            enableDiskCache: false,
            enableMemoryCache: false
        )
        let url = URL(string: "https://example.com/no-memory-cache.png")!

        ImageURLProtocol.reset()
        _ = try await downloader.image(for: url)
        _ = try await downloader.image(for: url)

        XCTAssertNil(try downloader.cachedImage(for: url))
        XCTAssertEqual(ImageURLProtocol.requestCount, 2)
    }

    func testDownloaderReturnsNilForCacheMiss() throws {
        let downloader = ImageDownloader(enableDiskCache: false)
        let url = URL(string: "https://example.com/not-loaded.png")!

        XCTAssertNil(try downloader.cachedImage(for: url))
    }

    func testDownloaderThrowsForCorruptDiskCache() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = URL(string: "https://example.com/corrupt.png")!
        let downloader = ImageDownloader(
            session: session,
            cacheDirectory: cacheDirectory
        )

        _ = try await downloader.image(for: url)
        let cachedFile = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        try Data("not-an-image".utf8).write(to: cachedFile, options: .atomic)

        let freshDownloader = ImageDownloader(
            session: session,
            cacheDirectory: cacheDirectory
        )
        XCTAssertThrowsError(try freshDownloader.cachedImage(for: url))
    }
}

private final class ImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedRequestCount = 0
    private static let imageData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    static func reset() {
        lock.lock()
        storedRequestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.storedRequestCount += 1
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.imageData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
