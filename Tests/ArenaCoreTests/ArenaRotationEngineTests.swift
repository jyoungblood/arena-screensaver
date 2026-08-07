import Foundation
import XCTest
@testable import ArenaCore

final class ArenaRotationEngineTests: XCTestCase {
    func testRotationBalancesChannels() {
        var engine = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: .all,
            recentCapacity: 4
        )
        engine.replaceContent(batch([
            channel("a", images: [image(1, channel: "a"), image(2, channel: "a")]),
            channel("b", images: [image(10, channel: "b"), image(11, channel: "b")])
        ]))

        let sequence = (0..<4).compactMap { _ in engine.nextImage()?.channelIdentifier }
        XCTAssertEqual(sequence, ["a", "b", "a", "b"])
    }

    func testRotationDoesNotRepeatWhileUnseenImagesRemain() {
        var engine = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: .all,
            recentCapacity: 20
        )
        let images = (1...25).map { image($0, channel: "a") }
        engine.replaceContent(batch([channel("a", images: images)]))

        let selected = (0..<25).compactMap { _ in engine.nextImage()?.id }
        XCTAssertEqual(Set(selected).count, 25)
    }

    func testRecentHistoryRemainsBoundedDuringLongSessions() {
        var engine = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: .all,
            recentCapacity: 20
        )
        let images = (1...30).map { image($0, channel: "a") }
        engine.replaceContent(batch([channel("a", images: images)]))

        for _ in 0..<10_000 {
            _ = engine.nextImage()
        }

        XCTAssertLessThanOrEqual(engine.retainedRecentImageCount, 20)
    }

    func testFailedImagesAreRemovedFromRotation() {
        var engine = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: .all
        )
        engine.replaceContent(batch([
            channel("a", images: [image(1, channel: "a"), image(2, channel: "a")])
        ]))

        XCTAssertEqual(engine.nextImage()?.id, 1)
        engine.markImageFailed(id: 1)
        XCTAssertEqual(engine.nextImage()?.id, 2)
        XCTAssertEqual(engine.nextImage()?.id, 2)
    }

    func testOrientationFiltersUseImageDimensions() {
        let images = [
            image(1, channel: "a", width: 1_600, height: 900),
            image(2, channel: "a", width: 900, height: 1_600),
            image(3, channel: "a", width: 1_000, height: 1_000)
        ]

        var landscape = ArenaRotationEngine(order: .channelOrder, orientationFilter: .landscape)
        landscape.replaceContent(batch([channel("a", images: images)]))
        XCTAssertEqual(landscape.nextImage()?.id, 1)

        var portrait = ArenaRotationEngine(order: .channelOrder, orientationFilter: .portrait)
        portrait.replaceContent(batch([channel("a", images: images)]))
        XCTAssertEqual(portrait.nextImage()?.id, 2)

        var square = ArenaRotationEngine(order: .channelOrder, orientationFilter: .square)
        square.replaceContent(batch([channel("a", images: images)]))
        XCTAssertEqual(square.nextImage()?.id, 3)

        var landscapeAndSquare = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: [.landscape, .square]
        )
        landscapeAndSquare.replaceContent(batch([channel("a", images: images)]))
        XCTAssertEqual(
            Set((0..<2).compactMap { _ in landscapeAndSquare.nextImage()?.id }),
            Set([1, 3])
        )
    }

    func testOrientationSelectionSerializationSupportsLegacyAndMultipleValues() {
        XCTAssertEqual(ImageOrientationFilter(serializedValue: "all"), .all)
        XCTAssertEqual(
            ImageOrientationFilter(serializedValue: "landscape"),
            .landscape
        )
        XCTAssertEqual(
            ImageOrientationFilter(serializedValue: "landscape,square"),
            [.landscape, .square]
        )
        XCTAssertEqual(
            ImageOrientationFilter.landscape.union(.portrait).serializedValue,
            "landscape,portrait"
        )
    }

    func testPaginationStartsWhenUnseenImagesRunLow() {
        var engine = ArenaRotationEngine(
            order: .channelOrder,
            orientationFilter: .all,
            pageThreshold: 1
        )
        engine.replaceContent(batch([
            channel(
                "a",
                images: [image(1, channel: "a"), image(2, channel: "a")],
                nextPage: 2
            )
        ]))

        XCTAssertNil(engine.nextPageRequest())
        _ = engine.nextImage()
        XCTAssertEqual(
            engine.nextPageRequest(),
            ArenaPageRequest(channelIdentifier: "a", page: 2)
        )
        XCTAssertNil(engine.nextPageRequest())
    }

    func testContentOrderMapsToSupportedAPISorts() {
        XCTAssertEqual(ContentOrder.channelOrder.apiSort, .channelOrderNewestFirst)
        XCTAssertEqual(ContentOrder.random.apiSort, .channelOrderNewestFirst)
        XCTAssertEqual(ContentOrder.newest.apiSort, .newest)
        XCTAssertEqual(ContentOrder.oldest.apiSort, .oldest)
    }

    private func batch(_ channels: [ArenaChannelContent]) -> ArenaContentBatch {
        ArenaContentBatch(channels: channels, failures: [])
    }

    private func channel(
        _ identifier: String,
        images: [ArenaImage],
        nextPage: Int? = nil
    ) -> ArenaChannelContent {
        ArenaChannelContent(
            id: identifier.hashValue,
            identifier: identifier,
            title: identifier.uppercased(),
            ownerName: nil,
            images: images,
            pagination: ArenaPagination(
                currentPage: 1,
                nextPage: nextPage,
                totalPages: nextPage == nil ? 1 : 2,
                totalCount: images.count,
                hasMorePages: nextPage != nil
            )
        )
    }

    private func image(
        _ id: Int,
        channel: String,
        width: Int = 1_600,
        height: Int = 900
    ) -> ArenaImage {
        ArenaImage(
            id: id,
            title: "Image \(id)",
            altText: nil,
            creatorName: nil,
            channelIdentifier: channel,
            channelTitle: channel.uppercased(),
            channelOwnerName: nil,
            width: width,
            height: height,
            createdAt: nil,
            updatedAt: nil,
            displayURL: URL(string: "https://images.are.na/\(id).jpg")!,
            retinaURL: URL(string: "https://images.are.na/\(id)@2x.jpg")!
        )
    }
}
