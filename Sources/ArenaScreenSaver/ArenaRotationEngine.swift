import Foundation

enum ContentOrder: String, CaseIterable, Sendable {
    case random
    case channelOrder
    case newest
    case oldest

    var title: String {
        switch self {
        case .random: return "Random"
        case .channelOrder: return "Channel order"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }

    var apiSort: ArenaContentSort {
        switch self {
        case .random, .channelOrder: return .channelOrderNewestFirst
        case .newest: return .newest
        case .oldest: return .oldest
        }
    }
}

struct ImageOrientationFilter: OptionSet, Sendable {
    let rawValue: Int

    static let landscape = ImageOrientationFilter(rawValue: 1 << 0)
    static let portrait = ImageOrientationFilter(rawValue: 1 << 1)
    static let square = ImageOrientationFilter(rawValue: 1 << 2)
    static let all: ImageOrientationFilter = [.landscape, .portrait, .square]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(serializedValue: String) {
        let values = Set(
            serializedValue
                .lowercased()
                .split(separator: ",")
                .map(String.init)
        )
        if values.isEmpty || values.contains("all") {
            self = .all
            return
        }

        var selection: ImageOrientationFilter = []
        if values.contains("landscape") { selection.insert(.landscape) }
        if values.contains("portrait") { selection.insert(.portrait) }
        if values.contains("square") { selection.insert(.square) }
        self = selection.isEmpty ? .all : selection
    }

    var serializedValue: String {
        if self == .all { return "all" }
        return [
            contains(.landscape) ? "landscape" : nil,
            contains(.portrait) ? "portrait" : nil,
            contains(.square) ? "square" : nil
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }

    func includes(_ image: ArenaImage) -> Bool {
        guard image.width > 0, image.height > 0 else { return false }
        let ratio = Double(image.width) / Double(image.height)
        if ratio > 1.1 { return contains(.landscape) }
        if ratio < 0.9 { return contains(.portrait) }
        return contains(.square)
    }
}

struct ArenaPageRequest: Equatable, Sendable {
    let channelIdentifier: String
    let page: Int
}

struct ArenaRotationEngine {
    private struct ChannelState {
        var content: ArenaChannelContent
        var images: [ArenaImage]
        var cursor = 0

        mutating func next(excluding excludedIDs: Set<Int>) -> ArenaImage? {
            guard !images.isEmpty else { return nil }
            for _ in 0..<images.count {
                let image = images[cursor % images.count]
                cursor = (cursor + 1) % images.count
                if !excludedIDs.contains(image.id) {
                    return image
                }
            }
            return nil
        }
    }

    private let recentCapacity: Int
    private let pageThreshold: Int
    private(set) var order: ContentOrder
    private(set) var orientationFilter: ImageOrientationFilter
    private var channelOrder: [String] = []
    private var channels: [String: ChannelState] = [:]
    private var channelCursor = 0
    private var pagingCursor = 0
    private var recentIDs: [Int] = []
    private var shownIDs = Set<Int>()
    private var failedImageIDs = Set<Int>()
    private var pageRequestsInFlight = Set<String>()
    private var pageFailures = Set<String>()

    init(
        order: ContentOrder = .random,
        orientationFilter: ImageOrientationFilter = .all,
        recentCapacity: Int = 20,
        pageThreshold: Int = 10
    ) {
        self.order = order
        self.orientationFilter = orientationFilter
        self.recentCapacity = max(recentCapacity, 0)
        self.pageThreshold = max(pageThreshold, 0)
    }

    var hasImages: Bool {
        channels.values.contains { state in
            state.images.contains { !failedImageIDs.contains($0.id) }
        }
    }

    var retainedRecentImageCount: Int {
        recentIDs.count
    }

    mutating func replaceContent(_ batch: ArenaContentBatch) {
        var seenIDs = Set<Int>()
        var replacement: [String: ChannelState] = [:]
        let identifiers = batch.channels.map(\.identifier)

        for content in batch.channels {
            var images = content.images.filter {
                orientationFilter.includes($0) && seenIDs.insert($0.id).inserted
            }
            if order == .random {
                images.shuffle()
            }
            replacement[content.identifier] = ChannelState(
                content: content,
                images: images
            )
        }

        channelOrder = identifiers
        channels = replacement
        channelCursor = 0
        pagingCursor = 0
        pageRequestsInFlight = []
        pageFailures = []
        let currentIDs = Set(channels.values.flatMap { $0.images.map(\.id) })
        recentIDs = recentIDs.filter(currentIDs.contains)
        shownIDs.formIntersection(currentIDs)
        failedImageIDs.formIntersection(currentIDs)
        trimRecentHistory()
    }

    mutating func appendPage(_ content: ArenaChannelContent) {
        guard var state = channels[content.identifier] else { return }
        let existingIDs = Set(channels.values.flatMap { $0.images.map(\.id) })
        var additions = content.images.filter {
            orientationFilter.includes($0) && !existingIDs.contains($0.id)
        }
        if order == .random {
            additions.shuffle()
        }
        state.images.append(contentsOf: additions)
        state.content = ArenaChannelContent(
            id: state.content.id,
            identifier: state.content.identifier,
            title: state.content.title,
            ownerName: state.content.ownerName,
            images: state.content.images + content.images,
            pagination: content.pagination
        )
        channels[content.identifier] = state
        pageRequestsInFlight.remove(content.identifier)
        pageFailures.remove(content.identifier)
        trimRecentHistory()
    }

    mutating func nextImage() -> ArenaImage? {
        guard hasImages, !channelOrder.isEmpty else { return nil }

        let usableImageCount = channels.values.reduce(0) { count, state in
            count + state.images.filter { !failedImageIDs.contains($0.id) }.count
        }
        let activeRecentCount = min(recentCapacity, max(usableImageCount - 1, 0))

        while true {
            let excludedIDs = failedImageIDs.union(recentIDs.suffix(activeRecentCount))
            for _ in 0..<channelOrder.count {
                let identifier = channelOrder[channelCursor % channelOrder.count]
                channelCursor = (channelCursor + 1) % channelOrder.count
                guard var state = channels[identifier] else { continue }
                let image = state.next(excluding: excludedIDs)
                channels[identifier] = state
                if let image {
                    shownIDs.insert(image.id)
                    recentIDs.append(image.id)
                    trimRecentHistory()
                    return image
                }
            }

            guard !recentIDs.isEmpty else { return nil }
            recentIDs.removeFirst()
        }
    }

    mutating func markImageFailed(id: Int) {
        failedImageIDs.insert(id)
        recentIDs.removeAll { $0 == id }
    }

    mutating func nextPageRequest() -> ArenaPageRequest? {
        guard !channelOrder.isEmpty else { return nil }
        for _ in 0..<channelOrder.count {
            let identifier = channelOrder[pagingCursor % channelOrder.count]
            pagingCursor = (pagingCursor + 1) % channelOrder.count
            guard let state = channels[identifier],
                  let nextPage = state.content.pagination.nextPage,
                  !pageRequestsInFlight.contains(identifier),
                  !pageFailures.contains(identifier) else { continue }

            let unseenCount = state.images.reduce(0) { count, image in
                count + (shownIDs.contains(image.id) ? 0 : 1)
            }
            guard unseenCount <= pageThreshold else { continue }
            pageRequestsInFlight.insert(identifier)
            return ArenaPageRequest(channelIdentifier: identifier, page: nextPage)
        }
        return nil
    }

    mutating func markPageRequestFailed(channelIdentifier: String) {
        pageRequestsInFlight.remove(channelIdentifier)
        pageFailures.insert(channelIdentifier)
    }

    func channelContent(identifier: String) -> ArenaChannelContent? {
        channels[identifier]?.content
    }

    private mutating func trimRecentHistory() {
        let total = channels.values.reduce(0) { $0 + $1.images.count }
        let limit = min(recentCapacity, max(total - 1, 0))
        if recentIDs.count > limit {
            recentIDs.removeFirst(recentIDs.count - limit)
        }
    }
}
