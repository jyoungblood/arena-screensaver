import CryptoKit
import Foundation

actor ArenaContentIndex {
    static let shared = ArenaContentIndex(fileURL: defaultFileURL)

    private struct Snapshot: Codable {
        var version = 1
        var records: [Record]
    }

    private struct Record: Codable {
        let identifier: String
        let sort: ArenaContentSort
        let updatedAt: Date
        let content: ArenaChannelContent
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("ArenaScreenSaver", isDirectory: true)
            .appendingPathComponent("content-index-v1.json")
    }

    private let fileURL: URL
    private var records: [String: Record] = [:]
    private var hasLoaded = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func content(identifier: String, sort: ArenaContentSort) -> ArenaChannelContent? {
        loadIfNeeded()
        return records[key(identifier: identifier, sort: sort)]?.content
    }

    func replace(_ content: ArenaChannelContent, sort: ArenaContentSort) throws {
        loadIfNeeded()
        records[key(identifier: content.identifier, sort: sort)] = Record(
            identifier: content.identifier,
            sort: sort,
            updatedAt: Date(),
            content: content
        )
        try persist()
    }

    func append(_ page: ArenaChannelContent, sort: ArenaContentSort) throws {
        loadIfNeeded()
        let recordKey = key(identifier: page.identifier, sort: sort)
        guard let existing = records[recordKey]?.content else {
            try replace(page, sort: sort)
            return
        }

        var seen = Set<Int>()
        let images = (existing.images + page.images).filter {
            seen.insert($0.id).inserted
        }
        let merged = ArenaChannelContent(
            id: existing.id,
            identifier: existing.identifier,
            title: page.title,
            ownerName: page.ownerName,
            images: images,
            pagination: page.pagination
        )
        records[recordKey] = Record(
            identifier: page.identifier,
            sort: sort,
            updatedAt: Date(),
            content: merged
        )
        try persist()
    }

    func clear() throws {
        records = [:]
        hasLoaded = true
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1 else { return }
        records = Dictionary(
            uniqueKeysWithValues: snapshot.records.map {
                (key(identifier: $0.identifier, sort: $0.sort), $0)
            }
        )
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let snapshot = Snapshot(records: Array(records.values))
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private func key(identifier: String, sort: ArenaContentSort) -> String {
        "\(identifier)|\(sort.rawValue)"
    }
}

actor ArenaImageCache {
    static let shared = ArenaImageCache(directoryURL: defaultDirectoryURL)

    private static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("ArenaScreenSaver", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
    }

    private let directoryURL: URL
    private var inFlightLoads: [String: Task<Data, Error>] = [:]
    private var cacheGeneration = 0

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func data(
        for url: URL,
        maximumBytes: Int64,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let destination = fileURL(for: url)
        if let data = try? Data(contentsOf: destination) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path
            )
            try? trim(to: maximumBytes)
            return data
        }

        let cacheKey = destination.lastPathComponent
        if let task = inFlightLoads[cacheKey] {
            return try await task.value
        }

        let generation = cacheGeneration
        let task = Task { try await loader() }
        inFlightLoads[cacheKey] = task
        do {
            let data = try await task.value
            inFlightLoads[cacheKey] = nil
            if generation == cacheGeneration {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: .atomic)
                try trim(to: maximumBytes)
            }
            return data
        } catch {
            inFlightLoads[cacheKey] = nil
            throw error
        }
    }

    func trim(to maximumBytes: Int64) throws {
        let files = try cachedFiles().sorted {
            $0.modificationDate < $1.modificationDate
        }
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        for file in files where total > max(maximumBytes, 0) {
            try FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    func size() throws -> Int64 {
        try cachedFiles().reduce(Int64(0)) { $0 + $1.size }
    }

    func clear() throws {
        cacheGeneration += 1
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
    }

    func remove(_ url: URL) throws {
        let cachedFile = fileURL(for: url)
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            try FileManager.default.removeItem(at: cachedFile)
        }
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent(digest)
    }

    private func cachedFiles() throws -> [(url: URL, size: Int64, modificationDate: Date)] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        return try FileManager.default
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            .compactMap { url in
                let values = try url.resourceValues(forKeys: keys)
                guard let size = values.fileSize else { return nil }
                return (url, Int64(size), values.contentModificationDate ?? .distantPast)
            }
    }
}
