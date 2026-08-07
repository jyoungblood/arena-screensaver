import Foundation
import XCTest
@testable import ArenaCore

final class ArenaAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.responseData = { _ in Data() }
        StubURLProtocol.statusCode = { _ in 200 }
        StubURLProtocol.responseHeaders = { _ in ["Content-Type": "application/json"] }
        StubURLProtocol.observedRequests = []
    }

    func testChannelIdentifierAcceptsSlug() throws {
        XCTAssertEqual(try ArenaAPIClient.channelIdentifier(from: "arena-influences"), "arena-influences")
    }

    func testChannelIdentifierExtractsSlugFromURL() throws {
        XCTAssertEqual(
            try ArenaAPIClient.channelIdentifier(from: "https://www.are.na/are-na-team/arena-influences?sort=position"),
            "arena-influences"
        )
        XCTAssertEqual(
            try ArenaAPIClient.channelIdentifier(from: "https://are.na/are-na-team/arena-influences/"),
            "arena-influences"
        )
    }

    func testChannelIdentifierRejectsOtherHosts() {
        XCTAssertThrowsError(try ArenaAPIClient.channelIdentifier(from: "https://example.com/a-channel"))
    }

    func testFetchContentIncludesChannelAttributionAndPagination() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ArenaAPIClient(session: URLSession(configuration: configuration))

        StubURLProtocol.responseData = { request in
            request.url?.path.hasSuffix("/contents") == true
                ? Data(Self.contentsFixture.utf8)
                : Data(Self.channelFixture.utf8)
        }
        let batch = try await client.fetchContent(from: ["test-channel"])
        let images = batch.images

        XCTAssertEqual(batch.channels.first?.title, "Test Channel")
        XCTAssertEqual(batch.channels.first?.ownerName, "Channel Owner")
        XCTAssertEqual(batch.channels.first?.pagination.nextPage, 2)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.id, 42)
        XCTAssertEqual(images.first?.creatorName, "Image Creator")
        XCTAssertEqual(images.first?.channelTitle, "Test Channel")
        XCTAssertEqual(images.first?.width, 1_600)
        XCTAssertEqual(images.first?.height, 900)
        XCTAssertEqual(images.first?.displayURL.absoluteString, "https://images.are.na/large.jpg")
        XCTAssertEqual(images.first?.retinaURL.absoluteString, "https://images.are.na/large@2x.jpg")
    }

    func testFetchPageUsesRequestedPageAndSort() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ArenaAPIClient(session: URLSession(configuration: configuration))

        StubURLProtocol.observedRequests = []
        StubURLProtocol.responseData = { request in
            request.url?.path.hasSuffix("/contents") == true
                ? Data(Self.contentsFixture.utf8)
                : Data(Self.channelFixture.utf8)
        }

        let batch = try await client.fetchContent(from: ["test-channel"])
        let channel = try XCTUnwrap(batch.channels.first)
        _ = try await client.fetchPage(after: channel, page: 2, sort: .oldest)

        let pageRequest = try XCTUnwrap(StubURLProtocol.observedRequests.last)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(pageRequest.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["per"], "50")
        XCTAssertEqual(query["sort"], ArenaContentSort.oldest.rawValue)
    }

    func testRetriesRateLimitedRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ArenaAPIClient(
            session: URLSession(configuration: configuration),
            retryPolicy: ArenaRetryPolicy(
                maximumAttempts: 3,
                baseDelay: 0,
                maximumDelay: 0
            )
        )

        StubURLProtocol.statusCode = { _ in
            StubURLProtocol.observedRequests.count == 1 ? 429 : 200
        }
        StubURLProtocol.responseHeaders = { _ in
            ["Content-Type": "application/json", "Retry-After": "0"]
        }
        StubURLProtocol.responseData = { request in
            request.url?.path.hasSuffix("/contents") == true
                ? Data(Self.contentsFixture.utf8)
                : Data(Self.channelFixture.utf8)
        }

        let batch = try await client.fetchContent(from: ["test-channel"])

        XCTAssertEqual(batch.images.count, 1)
        XCTAssertEqual(StubURLProtocol.observedRequests.count, 3)
    }

    func testUsesPersistentContentWhenChannelRequestFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = ArenaContentIndex(fileURL: root.appendingPathComponent("index.json"))
        let cached = Self.cachedChannelFixture
        try await index.replace(cached, sort: .channelOrderNewestFirst)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ArenaAPIClient(
            session: URLSession(configuration: configuration),
            contentIndex: index,
            retryPolicy: ArenaRetryPolicy(
                maximumAttempts: 1,
                baseDelay: 0,
                maximumDelay: 0
            )
        )
        StubURLProtocol.statusCode = { _ in 503 }

        let batch = try await client.fetchContent(from: ["test-channel"])

        XCTAssertEqual(batch.channels, [cached])
        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertTrue(batch.failures[0].isUsingCachedContent)
    }

    func testClassifiesOnlyRecoverableFailuresAsTransient() {
        XCTAssertTrue(ArenaAPIClient.isConnectivityFailure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(ArenaAPIClient.isTransientFailure(URLError(.networkConnectionLost)))
        XCTAssertTrue(ArenaAPIClient.isTransientFailure(
            ArenaAPIError.requestFailed(channel: "test", statusCode: 429)
        ))
        XCTAssertTrue(ArenaAPIClient.isTransientFailure(
            ArenaAPIError.requestFailed(channel: "test", statusCode: 503)
        ))
        XCTAssertFalse(ArenaAPIClient.isTransientFailure(
            ArenaAPIError.requestFailed(channel: "test", statusCode: 404)
        ))
        XCTAssertFalse(ArenaAPIClient.isTransientFailure(ArenaAPIError.invalidResponse))
    }

    private static let channelFixture = #"""
    {
      "id": 7,
      "title": "Test Channel",
      "slug": "test-channel",
      "owner": { "name": "Channel Owner" },
      "user": null
    }
    """#

    private static let contentsFixture = #"""
    {
      "data": [
        {
          "id": 42,
          "base_type": "Block",
          "type": "Image",
          "title": "A useful image",
          "state": "available",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-02T00:00:00Z",
          "user": { "name": "Image Creator" },
          "image": {
            "alt_text": "Description",
            "width": 1600,
            "height": 900,
            "large": {
              "src": "https://images.are.na/large.jpg",
              "src_2x": "https://images.are.na/large@2x.jpg"
            }
          }
        },
        {
          "id": 43,
          "base_type": "Block",
          "type": "Text",
          "title": "Not an image",
          "state": "available"
        }
      ],
      "meta": {
        "current_page": 1,
        "next_page": 2,
        "total_pages": 3,
        "total_count": 120,
        "has_more_pages": true
      }
    }
    """#

    private static let cachedChannelFixture = ArenaChannelContent(
        id: 7,
        identifier: "test-channel",
        title: "Saved Test Channel",
        ownerName: "Channel Owner",
        images: [ArenaImage(
            id: 42,
            title: "Saved image",
            altText: nil,
            creatorName: nil,
            channelIdentifier: "test-channel",
            channelTitle: "Saved Test Channel",
            channelOwnerName: "Channel Owner",
            width: 1_600,
            height: 900,
            createdAt: nil,
            updatedAt: nil,
            displayURL: URL(string: "https://images.are.na/saved.jpg")!,
            retinaURL: URL(string: "https://images.are.na/saved@2x.jpg")!
        )],
        pagination: ArenaPagination(
            currentPage: 1,
            nextPage: nil,
            totalPages: 1,
            totalCount: 1,
            hasMorePages: false
        )
    )
}

private final class StubURLProtocol: URLProtocol {
    static var responseData: (URLRequest) -> Data = { _ in Data() }
    static var statusCode: (URLRequest) -> Int = { _ in 200 }
    static var responseHeaders: (URLRequest) -> [String: String] = { _ in
        ["Content-Type": "application/json"]
    }
    static var observedRequests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.observedRequests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode(request),
            httpVersion: "HTTP/1.1",
            headerFields: Self.responseHeaders(request)
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData(request))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
