import Foundation

struct ArenaImage: Codable, Equatable, Sendable {
    let id: Int
    let title: String?
    let altText: String?
    let creatorName: String?
    let channelIdentifier: String
    let channelTitle: String
    let channelOwnerName: String?
    let width: Int
    let height: Int
    let createdAt: String?
    let updatedAt: String?
    let displayURL: URL
    let retinaURL: URL
}

struct ArenaPagination: Codable, Equatable, Sendable {
    let currentPage: Int
    let nextPage: Int?
    let totalPages: Int
    let totalCount: Int
    let hasMorePages: Bool
}

struct ArenaChannelContent: Codable, Equatable, Sendable {
    let id: Int
    let identifier: String
    let title: String
    let ownerName: String?
    let images: [ArenaImage]
    let pagination: ArenaPagination
}

struct ArenaChannelFailure: Codable, Equatable, Sendable {
    let identifier: String
    let message: String
    let isUsingCachedContent: Bool

    init(identifier: String, message: String, isUsingCachedContent: Bool = false) {
        self.identifier = identifier
        self.message = message
        self.isUsingCachedContent = isUsingCachedContent
    }
}

struct ArenaContentBatch: Codable, Equatable, Sendable {
    let channels: [ArenaChannelContent]
    let failures: [ArenaChannelFailure]

    var images: [ArenaImage] {
        var seenIDs = Set<Int>()
        return channels
            .flatMap(\.images)
            .filter { seenIDs.insert($0.id).inserted }
    }
}

enum ArenaContentSort: String, CaseIterable, Codable, Sendable {
    case channelOrderNewestFirst = "position_desc"
    case channelOrderOldestFirst = "position_asc"
    case newest = "created_at_desc"
    case oldest = "created_at_asc"
}

enum ArenaAPIError: LocalizedError {
    case invalidChannel(String)
    case invalidResponse
    case requestFailed(channel: String, statusCode: Int)
    case noImages([String])
    case tooManyChannels(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .invalidChannel(let value):
            return "\(value) is not a valid Are.na channel."
        case .invalidResponse:
            return "Are.na returned a response the screen saver could not read."
        case .requestFailed(let channel, let statusCode):
            return "Are.na returned HTTP \(statusCode) for \(channel)."
        case .noImages(let channels):
            return "No image blocks were found in \(channels.joined(separator: ", "))."
        case .tooManyChannels(let maximum):
            return "Add no more than \(maximum) channels."
        }
    }
}

struct ArenaRetryPolicy: Sendable {
    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval

    static let standard = ArenaRetryPolicy(
        maximumAttempts: 3,
        baseDelay: 0.75,
        maximumDelay: 30
    )
}

final class ArenaAPIClient: @unchecked Sendable {
    static let shared = ArenaAPIClient()

    private let session: URLSession
    private let contentIndex: ArenaContentIndex?
    private let imageCache: ArenaImageCache?
    private let retryPolicy: ArenaRetryPolicy
    private let decoder = JSONDecoder()
    private let sequentialRequestDelay: UInt64

    init(
        session: URLSession? = nil,
        contentIndex: ArenaContentIndex? = nil,
        imageCache: ArenaImageCache? = nil,
        retryPolicy: ArenaRetryPolicy = .standard
    ) {
        self.retryPolicy = retryPolicy
        if let session {
            self.session = session
            self.contentIndex = contentIndex
            self.imageCache = imageCache
            self.sequentialRequestDelay = 0
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "ArenaScreenSaver/0.1"
        ]
        self.session = URLSession(configuration: configuration)
        self.contentIndex = contentIndex ?? .shared
        self.imageCache = imageCache ?? .shared
        self.sequentialRequestDelay = 200_000_000
    }

    func fetchImages(from rawChannels: [String]) async throws -> [ArenaImage] {
        let batch = try await fetchContent(from: rawChannels)
        let images = batch.images
        if images.isEmpty {
            if let failure = batch.failures.last {
                throw ArenaAPIError.invalidChannel("\(failure.identifier): \(failure.message)")
            }
            throw ArenaAPIError.noImages(rawChannels)
        }
        return images
    }

    func fetchContent(
        from rawChannels: [String],
        sort: ArenaContentSort = .channelOrderNewestFirst
    ) async throws -> ArenaContentBatch {
        let channels = try rawChannels.map(Self.channelIdentifier(from:))
        guard channels.count <= 10 else { throw ArenaAPIError.tooManyChannels(maximum: 10) }
        var loadedChannels: [ArenaChannelContent] = []
        var failures: [ArenaChannelFailure] = []

        for (index, channel) in channels.enumerated() {
            do {
                let summary = try await fetchChannel(identifier: channel)
                if sequentialRequestDelay > 0 {
                    try await Task.sleep(nanoseconds: sequentialRequestDelay)
                }
                loadedChannels.append(
                    try await fetchPage(channel: summary, page: 1, sort: sort)
                )
            } catch {
                let cachedContent = await contentIndex?.content(
                    identifier: channel,
                    sort: sort
                )
                if let cachedContent {
                    loadedChannels.append(cachedContent)
                }
                failures.append(ArenaChannelFailure(
                    identifier: channel,
                    message: cachedContent == nil
                        ? error.localizedDescription
                        : "\(error.localizedDescription) Showing saved content.",
                    isUsingCachedContent: cachedContent != nil
                ))
            }
            if index < channels.count - 1 {
                try await Task.sleep(nanoseconds: max(sequentialRequestDelay, 250_000_000))
            }
        }

        return ArenaContentBatch(channels: loadedChannels, failures: failures)
    }

    func fetchImageData(
        from url: URL,
        maximumCacheBytes: Int64 = 512 * 1_024 * 1_024
    ) async throws -> Data {
        if let imageCache {
            return try await imageCache.data(for: url, maximumBytes: maximumCacheBytes) {
                try await self.downloadImageData(from: url)
            }
        }
        return try await downloadImageData(from: url)
    }

    func clearCaches() async throws {
        try await contentIndex?.clear()
        try await imageCache?.clear()
    }

    func trimImageCache(to maximumBytes: Int64) async throws {
        try await imageCache?.trim(to: maximumBytes)
    }

    func imageCacheSize() async throws -> Int64 {
        try await imageCache?.size() ?? 0
    }

    func invalidateCachedImage(at url: URL) async {
        try? await imageCache?.remove(url)
    }

    func fetchPage(
        after channel: ArenaChannelContent,
        page: Int,
        sort: ArenaContentSort
    ) async throws -> ArenaChannelContent {
        let owner = channel.ownerName.map { ArenaIdentity(name: $0) }
        let summary = ChannelResponse(
            id: channel.id,
            title: channel.title,
            slug: channel.identifier,
            owner: owner,
            user: nil
        )
        return try await fetchPage(channel: summary, page: page, sort: sort)
    }

    static func channelIdentifier(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ArenaAPIError.invalidChannel(input) }

        if let url = URL(string: trimmed), let host = url.host {
            let normalizedHost = host.lowercased()
            guard normalizedHost == "are.na" || normalizedHost == "www.are.na" else {
                throw ArenaAPIError.invalidChannel(input)
            }
            guard let identifier = url.pathComponents
                .filter({ $0 != "/" && !$0.isEmpty })
                .last else {
                throw ArenaAPIError.invalidChannel(input)
            }
            return identifier
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ArenaAPIError.invalidChannel(input)
        }
        return trimmed
    }

    static func isConnectivityFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet
        ].contains(urlError.code)
    }

    static func isTransientFailure(_ error: Error) -> Bool {
        if isConnectivityFailure(error) { return true }
        guard let apiError = error as? ArenaAPIError,
              case .requestFailed(_, let statusCode) = apiError else {
            return false
        }
        return statusCode == 429 || (500...599).contains(statusCode)
    }

    private func fetchChannel(identifier: String) async throws -> ChannelResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.are.na"
        components.path = "/v3/channels/\(identifier)"
        guard let url = components.url else { throw ArenaAPIError.invalidChannel(identifier) }
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        let data = try await responseData(for: request, channel: identifier)
        return try decoder.decode(ChannelResponse.self, from: data)
    }

    private func fetchPage(
        channel: ChannelResponse,
        page: Int,
        sort: ArenaContentSort
    ) async throws -> ArenaChannelContent {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.are.na"
        components.path = "/v3/channels/\(channel.slug)/contents"
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per", value: "50"),
            URLQueryItem(name: "sort", value: sort.rawValue)
        ]
        guard let url = components.url else { throw ArenaAPIError.invalidChannel(channel.slug) }

        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        let data = try await responseData(for: request, channel: channel.slug)
        let payload = try decoder.decode(ContentsResponse.self, from: data)
        let ownerName = channel.owner?.name ?? channel.user?.name
        let images: [ArenaImage] = payload.data.compactMap { block -> ArenaImage? in
            guard block.baseType == "Block",
                  block.type == "Image",
                  block.state == "available",
                  let image = block.image,
                  let displayURL = URL(string: image.large.src)
            else { return nil }

            return ArenaImage(
                id: block.id,
                title: block.title,
                altText: image.altText,
                creatorName: block.user?.name,
                channelIdentifier: channel.slug,
                channelTitle: channel.title,
                channelOwnerName: ownerName,
                width: image.width,
                height: image.height,
                createdAt: block.createdAt,
                updatedAt: block.updatedAt,
                displayURL: displayURL,
                retinaURL: URL(string: image.large.src2x ?? image.large.src) ?? displayURL
            )
        }

        let content = ArenaChannelContent(
            id: channel.id,
            identifier: channel.slug,
            title: channel.title,
            ownerName: ownerName,
            images: images,
            pagination: ArenaPagination(
                currentPage: payload.meta.currentPage,
                nextPage: payload.meta.nextPage,
                totalPages: payload.meta.totalPages,
                totalCount: payload.meta.totalCount,
                hasMorePages: payload.meta.hasMorePages
            )
        )
        if page == 1 {
            try? await contentIndex?.replace(content, sort: sort)
        } else {
            try? await contentIndex?.append(content, sort: sort)
        }
        return content
    }

    private func responseData(for request: URLRequest, channel: String) async throws -> Data {
        let maximumAttempts = max(retryPolicy.maximumAttempts, 1)
        for attempt in 1...maximumAttempts {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ArenaAPIError.invalidResponse
                }
                if (200..<300).contains(httpResponse.statusCode) {
                    return data
                }
                guard shouldRetry(statusCode: httpResponse.statusCode),
                      attempt < maximumAttempts else {
                    throw ArenaAPIError.requestFailed(
                        channel: channel,
                        statusCode: httpResponse.statusCode
                    )
                }
                try await waitBeforeRetry(response: httpResponse, attempt: attempt)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard shouldRetry(error: error), attempt < maximumAttempts else { throw error }
                try await waitBeforeRetry(response: nil, attempt: attempt)
            }
        }
        throw ArenaAPIError.invalidResponse
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        return try await responseData(for: request, channel: "image")
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        Self.isConnectivityFailure(error)
    }

    private func waitBeforeRetry(
        response: HTTPURLResponse?,
        attempt: Int
    ) async throws {
        let exponential = retryPolicy.baseDelay * pow(2, Double(attempt - 1))
        let retryAfter = response.flatMap(retryAfterDelay)
        let delay = min(max(retryAfter ?? exponential, 0), retryPolicy.maximumDelay)
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func retryAfterDelay(response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) { return seconds }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(date.timeIntervalSinceNow, 0)
    }
}

private struct ChannelResponse: Decodable {
    let id: Int
    let title: String
    let slug: String
    let owner: ArenaIdentity?
    let user: ArenaIdentity?
}

private struct ArenaIdentity: Decodable {
    let name: String
}

private struct ContentsResponse: Decodable {
    let data: [ContentBlock]
    let meta: PaginationPayload
}

private struct PaginationPayload: Decodable {
    let currentPage: Int
    let nextPage: Int?
    let totalPages: Int
    let totalCount: Int
    let hasMorePages: Bool

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case nextPage = "next_page"
        case totalPages = "total_pages"
        case totalCount = "total_count"
        case hasMorePages = "has_more_pages"
    }
}

private struct ContentBlock: Decodable {
    let id: Int
    let baseType: String
    let type: String?
    let title: String?
    let state: String?
    let image: BlockImage?
    let user: ArenaIdentity?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case baseType = "base_type"
        case type
        case title
        case state
        case image
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct BlockImage: Decodable {
    let altText: String?
    let width: Int
    let height: Int
    let large: ImageVersion

    enum CodingKeys: String, CodingKey {
        case altText = "alt_text"
        case width
        case height
        case large
    }
}

private struct ImageVersion: Decodable {
    let src: String
    let src2x: String?

    enum CodingKeys: String, CodingKey {
        case src
        case src2x = "src_2x"
    }
}
