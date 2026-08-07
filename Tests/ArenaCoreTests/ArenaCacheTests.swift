import Foundation
import XCTest
@testable import ArenaCore

final class ArenaCacheTests: XCTestCase {
    func testContentIndexPersistsAndAppendsPages() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("content-index.json")
        let firstPage = channel(images: [image(1)], nextPage: 2)
        let secondPage = channel(images: [image(2)], currentPage: 2)

        let index = ArenaContentIndex(fileURL: fileURL)
        try await index.replace(firstPage, sort: .newest)
        try await index.append(secondPage, sort: .newest)

        let reloaded = ArenaContentIndex(fileURL: fileURL)
        let content = await reloaded.content(identifier: "test", sort: .newest)
        let otherSort = await reloaded.content(identifier: "test", sort: .oldest)

        XCTAssertEqual(content?.images.map(\.id), [1, 2])
        XCTAssertEqual(content?.pagination.currentPage, 2)
        XCTAssertNil(otherSort)
    }

    func testImageCacheReusesDownloadsAndClearsFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ArenaImageCache(directoryURL: root.appendingPathComponent("images"))
        let url = URL(string: "https://images.are.na/test.jpg")!
        let expected = Data([1, 2, 3, 4])

        let first = try await cache.data(for: url, maximumBytes: 100) { expected }
        let second = try await cache.data(for: url, maximumBytes: 100) {
            XCTFail("The cached file should avoid a second download.")
            return Data()
        }
        let populatedSize = try await cache.size()

        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
        XCTAssertEqual(populatedSize, 4)
        try await cache.remove(url)
        let removedSize = try await cache.size()
        XCTAssertEqual(removedSize, 0)
        _ = try await cache.data(for: url, maximumBytes: 100) { expected }
        try await cache.clear()
        let clearedSize = try await cache.size()
        XCTAssertEqual(clearedSize, 0)
    }

    func testImageCacheTrimsLeastRecentlyUsedFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ArenaImageCache(directoryURL: root.appendingPathComponent("images"))
        let firstURL = URL(string: "https://images.are.na/first.jpg")!
        let secondURL = URL(string: "https://images.are.na/second.jpg")!

        _ = try await cache.data(for: firstURL, maximumBytes: 8) {
            Data(repeating: 1, count: 6)
        }
        _ = try await cache.data(for: secondURL, maximumBytes: 8) {
            Data(repeating: 2, count: 6)
        }
        let size = try await cache.size()

        XCTAssertLessThanOrEqual(size, 8)
    }

    func testImageCacheSharesAnInFlightDownload() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ArenaImageCache(directoryURL: root.appendingPathComponent("images"))
        let counter = LoadCounter()
        let url = URL(string: "https://images.are.na/shared.jpg")!

        async let first = cache.data(for: url, maximumBytes: 100) {
            await counter.increment()
            try await Task.sleep(nanoseconds: 20_000_000)
            return Data([1, 2, 3])
        }
        async let second = cache.data(for: url, maximumBytes: 100) {
            await counter.increment()
            try await Task.sleep(nanoseconds: 20_000_000)
            return Data([1, 2, 3])
        }

        let results = try await [first, second]
        let loadCount = await counter.value
        XCTAssertEqual(results, [Data([1, 2, 3]), Data([1, 2, 3])])
        XCTAssertEqual(loadCount, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func channel(
        images: [ArenaImage],
        currentPage: Int = 1,
        nextPage: Int? = nil
    ) -> ArenaChannelContent {
        ArenaChannelContent(
            id: 1,
            identifier: "test",
            title: "Test",
            ownerName: nil,
            images: images,
            pagination: ArenaPagination(
                currentPage: currentPage,
                nextPage: nextPage,
                totalPages: nextPage == nil ? currentPage : currentPage + 1,
                totalCount: images.count,
                hasMorePages: nextPage != nil
            )
        )
    }

    private func image(_ id: Int) -> ArenaImage {
        ArenaImage(
            id: id,
            title: "Image \(id)",
            altText: nil,
            creatorName: nil,
            channelIdentifier: "test",
            channelTitle: "Test",
            channelOwnerName: nil,
            width: 1_600,
            height: 900,
            createdAt: nil,
            updatedAt: nil,
            displayURL: URL(string: "https://images.are.na/\(id).jpg")!,
            retinaURL: URL(string: "https://images.are.na/\(id)@2x.jpg")!
        )
    }
}

private actor LoadCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
