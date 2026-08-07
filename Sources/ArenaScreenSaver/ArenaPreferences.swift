import AppKit
import Foundation
import ScreenSaver

enum ImageScalingMode: String, CaseIterable {
    case fill
    case fit
    case fitWithMargins

    var title: String {
        switch self {
        case .fill: return "Fill screen"
        case .fit: return "Fit whole image"
        case .fitWithMargins: return "Fit with margins"
        }
    }
}

enum AnimationStyle: String, CaseIterable {
    case crossfade
    case stack

    var title: String {
        switch self {
        case .crossfade: return "Crossfade"
        case .stack: return "Stack"
        }
    }
}

struct ArenaPreferences {
    static let bundleIdentifier = "com.arena.screensaver"
    static let defaultChannel = "arena-influences"
    static let imageCacheSizeOptions = [128, 256, 512, 1_024, 2_048]

    var channels: [String]
    var slideDuration: TimeInterval
    var crossfadeDuration: TimeInterval
    var animationStyle: AnimationStyle
    var scalingMode: ImageScalingMode
    var contentOrder: ContentOrder
    var orientationFilter: ImageOrientationFilter
    var backgroundColor: NSColor
    var imageCacheSizeMB: Int
    var showsTitles: Bool

    var imageCacheLimitBytes: Int64 {
        Int64(imageCacheSizeMB) * 1_024 * 1_024
    }

    static func load() -> ArenaPreferences {
        let defaults = ScreenSaverDefaults(forModuleWithName: bundleIdentifier)
        defaults?.register(defaults: [
            Keys.channels: defaultChannel,
            Keys.slideDuration: 12.0,
            Keys.crossfadeDuration: 1.2,
            Keys.animationStyle: AnimationStyle.crossfade.rawValue,
            Keys.scalingMode: ImageScalingMode.fill.rawValue,
            Keys.contentOrder: ContentOrder.random.rawValue,
            Keys.orientationFilter: ImageOrientationFilter.all.serializedValue,
            Keys.backgroundColor: "#000000",
            Keys.imageCacheSizeMB: 512,
            Keys.shufflesImages: true,
            Keys.showsTitles: false
        ])
        if defaults?.integer(forKey: Keys.titleDefaultVersion) ?? 0 < 1 {
            defaults?.set(false, forKey: Keys.showsTitles)
            defaults?.set(1, forKey: Keys.titleDefaultVersion)
        }

        let channelString = defaults?.string(forKey: Keys.channels) ?? defaultChannel
        let channels = Self.parseChannels(channelString)
        let duration = defaults?.double(forKey: Keys.slideDuration) ?? 12
        let crossfadeDuration = defaults?.double(forKey: Keys.crossfadeDuration) ?? 1.2
        let animationStyle = AnimationStyle(
            rawValue: defaults?.string(forKey: Keys.animationStyle) ?? ""
        ) ?? .crossfade
        let scaling = ImageScalingMode(
            rawValue: defaults?.string(forKey: Keys.scalingMode) ?? ""
        ) ?? .fill
        let legacyOrder: ContentOrder = (defaults?.bool(forKey: Keys.shufflesImages) ?? true)
            ? .random
            : .channelOrder
        let contentOrder = ContentOrder(
            rawValue: defaults?.string(forKey: Keys.contentOrder) ?? ""
        ) ?? legacyOrder
        let orientationFilter = ImageOrientationFilter(
            serializedValue: defaults?.string(forKey: Keys.orientationFilter) ?? "all"
        )
        let backgroundColor = NSColor(
            arenaHex: defaults?.string(forKey: Keys.backgroundColor) ?? "#000000"
        ) ?? .black
        let storedCacheSize = defaults?.integer(forKey: Keys.imageCacheSizeMB) ?? 512
        let imageCacheSizeMB = imageCacheSizeOptions.contains(storedCacheSize)
            ? storedCacheSize
            : 512

        return ArenaPreferences(
            channels: channels.isEmpty ? [defaultChannel] : channels,
            slideDuration: min(max(duration, 1), 120),
            crossfadeDuration: min(max(crossfadeDuration, 0.2), 3),
            animationStyle: animationStyle,
            scalingMode: scaling,
            contentOrder: contentOrder,
            orientationFilter: orientationFilter,
            backgroundColor: backgroundColor,
            imageCacheSizeMB: imageCacheSizeMB,
            showsTitles: defaults?.bool(forKey: Keys.showsTitles) ?? false
        )
    }

    func save() {
        guard let defaults = ScreenSaverDefaults(forModuleWithName: Self.bundleIdentifier) else {
            return
        }
        defaults.set(channels.joined(separator: "\n"), forKey: Keys.channels)
        defaults.set(slideDuration, forKey: Keys.slideDuration)
        defaults.set(crossfadeDuration, forKey: Keys.crossfadeDuration)
        defaults.set(animationStyle.rawValue, forKey: Keys.animationStyle)
        defaults.set(scalingMode.rawValue, forKey: Keys.scalingMode)
        defaults.set(contentOrder.rawValue, forKey: Keys.contentOrder)
        defaults.set(orientationFilter.serializedValue, forKey: Keys.orientationFilter)
        defaults.set(backgroundColor.arenaHex, forKey: Keys.backgroundColor)
        defaults.set(imageCacheSizeMB, forKey: Keys.imageCacheSizeMB)
        defaults.set(showsTitles, forKey: Keys.showsTitles)
        defaults.synchronize()
    }

    static func parseChannels(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum Keys {
        static let channels = "channels"
        static let slideDuration = "slideDuration"
        static let crossfadeDuration = "crossfadeDuration"
        static let animationStyle = "animationStyle"
        static let scalingMode = "scalingMode"
        static let contentOrder = "contentOrder"
        static let orientationFilter = "orientationFilter"
        static let backgroundColor = "backgroundColor"
        static let imageCacheSizeMB = "imageCacheSizeMB"
        static let shufflesImages = "shufflesImages"
        static let showsTitles = "showsTitles"
        static let titleDefaultVersion = "titleDefaultVersion"
    }
}

private extension NSColor {
    convenience init?(arenaHex: String) {
        let value = arenaHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        let red = CGFloat((rgb >> 16) & 0xff) / 255
        let green = CGFloat((rgb >> 8) & 0xff) / 255
        let blue = CGFloat(rgb & 0xff) / 255
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }

    var arenaHex: String {
        guard let color = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
