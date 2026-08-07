import AppKit
import ImageIO
import Network
import QuartzCore
import ScreenSaver

private final class CaptionTextField: NSTextField {
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 3

    init(_ string: String) {
        super.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(
            width: size.width + horizontalPadding * 2,
            height: size.height + verticalPadding * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        cell?.draw(
            withFrame: bounds.insetBy(dx: horizontalPadding, dy: verticalPadding),
            in: self
        )
    }
}

private final class StackCanvasView: NSView {
    private var bitmap: NSBitmapImageRep?
    private var canvasSize = NSSize.zero
    var backgroundColor: NSColor = .black {
        didSet {
            bitmap = nil
            canvasSize = .zero
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { true }

    func reset(scale: CGFloat) {
        bitmap = nil
        canvasSize = .zero
        prepareCanvas(scale: scale)
        needsDisplay = true
    }

    func paint(_ image: NSImage, in destination: NSRect, scale: CGFloat) {
        if canvasSize != bounds.size {
            prepareCanvas(scale: scale)
        }
        guard let bitmap,
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        bitmap?.draw(in: bounds)
    }

    private func prepareCanvas(scale: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let resolvedScale = max(scale, 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(Int((bounds.width * resolvedScale).rounded()), 1),
            pixelsHigh: max(Int((bounds.height * resolvedScale).rounded()), 1),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        bitmap.size = bounds.size
        canvasSize = bounds.size
        self.bitmap = bitmap
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        backgroundColor.setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private struct PreparedArenaImage {
    let image: NSImage
    let metadata: ArenaImage
}

@objc(ArenaScreenSaverView)
final class ArenaScreenSaverView: ScreenSaverView {
    private var currentCanvas = ImageCanvasView()
    private var incomingCanvas = ImageCanvasView()
    private let stackCanvas = StackCanvasView()
    private let statusLabel = CaptionTextField("Connecting to Are.na…")
    private let titleLabel = CaptionTextField("")
    private let channelErrorLabel = CaptionTextField("")

    private var preferences = ArenaPreferences.load()
    private var rotationEngine = ArenaRotationEngine()
    private var lastAdvance = Date.distantPast
    private var preparedImage: PreparedArenaImage?
    private var hasDisplayedImage = false
    private var isTransitioning = false
    private var loadGeneration = 0
    private var contentTask: Task<Void, Never>?
    private var imageTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var channelErrorTask: Task<Void, Never>?
    private var imageRetryTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var configurationController: ConfigurationWindowController?
    private var networkMonitor: NWPathMonitor?
    private let networkQueue = DispatchQueue(label: "com.arena.screensaver.network")
    private var networkIsAvailable = true
    private var isSuspended = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private static let refreshInterval: UInt64 = 15 * 60 * 1_000_000_000

    override init?(frame frameRect: NSRect, isPreview: Bool) {
        super.init(frame: frameRect, isPreview: isPreview)
        setUpView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpView()
    }

    private func setUpView() {
        animationTimeInterval = 1
        wantsLayer = true
        layer?.backgroundColor = preferences.backgroundColor.cgColor

        for canvas in [currentCanvas, incomingCanvas] {
            canvas.frame = bounds
            canvas.autoresizingMask = [.width, .height]
            canvas.scalingMode = preferences.scalingMode
            canvas.backgroundColor = preferences.backgroundColor
            addSubview(canvas)
        }
        incomingCanvas.alphaValue = 0

        stackCanvas.frame = bounds
        stackCanvas.autoresizingMask = [.width, .height]
        stackCanvas.backgroundColor = preferences.backgroundColor
        stackCanvas.isHidden = true
        addSubview(stackCanvas)

        statusLabel.font = .systemFont(ofSize: isPreview ? 11 : 18, weight: .regular)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        titleLabel.font = .systemFont(ofSize: isPreview ? 9 : 14, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = true
        addSubview(titleLabel)

        channelErrorLabel.font = .systemFont(ofSize: isPreview ? 9 : 13, weight: .regular)
        channelErrorLabel.textColor = .white
        channelErrorLabel.maximumNumberOfLines = 10
        channelErrorLabel.lineBreakMode = .byWordWrapping
        channelErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        channelErrorLabel.isHidden = true
        addSubview(channelErrorLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isPreview ? 10 : 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: isPreview ? -10 : -28),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: isPreview ? -8 : -24),
            channelErrorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isPreview ? 10 : 28),
            channelErrorLabel.topAnchor.constraint(equalTo: topAnchor, constant: isPreview ? 10 : 28),
            channelErrorLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7)
        ])
    }

    override func startAnimation() {
        super.startAnimation()
        isSuspended = false
        startObservingSystemLifecycle()
        startNetworkMonitoring()
        reloadContent(using: ArenaPreferences.load())
    }

    override func stopAnimation() {
        loadGeneration += 1
        contentTask?.cancel()
        imageTask?.cancel()
        paginationTask?.cancel()
        refreshTask?.cancel()
        channelErrorTask?.cancel()
        imageRetryTask?.cancel()
        wakeTask?.cancel()
        contentTask = nil
        imageTask = nil
        paginationTask = nil
        refreshTask = nil
        channelErrorTask = nil
        imageRetryTask = nil
        wakeTask = nil
        preparedImage = nil
        isTransitioning = false
        isSuspended = true
        stopNetworkMonitoring()
        stopObservingSystemLifecycle()
        super.stopAnimation()
    }

    override func animateOneFrame() {
        guard !isSuspended,
              hasDisplayedImage,
              !isTransitioning,
              Date().timeIntervalSince(lastAdvance) >= preferences.slideDuration else { return }
        if preparedImage != nil {
            displayPreparedImage()
        } else {
            prepareNextImage()
        }
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = ConfigurationWindowController(preferences: ArenaPreferences.load()) { [weak self] preferences in
            guard let self, self.isAnimating else { return }
            self.reloadContent(using: preferences)
        }
        configurationController = controller
        return controller.window
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshPreparedImageForDisplayChange()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        refreshPreparedImageForDisplayChange()
    }

    private func refreshPreparedImageForDisplayChange() {
        guard isAnimating, !isSuspended else { return }
        imageTask?.cancel()
        imageTask = nil
        preparedImage = nil
        if preferences.animationStyle == .stack {
            stackCanvas.reset(scale: window?.backingScaleFactor ?? 2)
        }
        prepareNextImage()
    }

    private func startNetworkMonitoring() {
        stopNetworkMonitoring()
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let isAvailable = path.status == .satisfied
                let wasUnavailable = !self.networkIsAvailable
                self.networkIsAvailable = isAvailable
                guard isAvailable,
                      wasUnavailable,
                      self.isAnimating,
                      !self.isSuspended else { return }
                self.imageRetryTask?.cancel()
                self.imageRetryTask = nil
                self.reloadContent(using: self.preferences)
            }
        }
        monitor.start(queue: networkQueue)
    }

    private func stopNetworkMonitoring() {
        networkMonitor?.pathUpdateHandler = nil
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func startObservingSystemLifecycle() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.suspendForSystemSleep()
            },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resumeAfterSystemWake()
            }
        ]
    }

    private func stopObservingSystemLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers = []
    }

    private func suspendForSystemSleep() {
        guard !isSuspended else { return }
        isSuspended = true
        loadGeneration += 1
        for task in [contentTask, imageTask, paginationTask, refreshTask, imageRetryTask] {
            task?.cancel()
        }
        contentTask = nil
        imageTask = nil
        paginationTask = nil
        refreshTask = nil
        imageRetryTask = nil
        preparedImage = nil
        isTransitioning = false
        currentCanvas.layer?.removeAllAnimations()
        incomingCanvas.layer?.removeAllAnimations()
    }

    private func resumeAfterSystemWake() {
        guard isSuspended, isAnimating else { return }
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.isAnimating else { return }
                self.wakeTask = nil
                self.isSuspended = false
                self.reloadContent(using: self.preferences)
            }
        }
    }

    private func reloadContent(using preferences: ArenaPreferences) {
        guard !isSuspended else { return }
        loadGeneration += 1
        let generation = loadGeneration
        contentTask?.cancel()
        imageTask?.cancel()
        paginationTask?.cancel()
        refreshTask?.cancel()
        channelErrorTask?.cancel()
        imageRetryTask?.cancel()
        imageTask = nil
        paginationTask = nil
        refreshTask = nil
        channelErrorTask = nil
        imageRetryTask = nil
        self.preferences = preferences
        rotationEngine = ArenaRotationEngine(
            order: preferences.contentOrder,
            orientationFilter: preferences.orientationFilter
        )
        currentCanvas.scalingMode = preferences.scalingMode
        incomingCanvas.scalingMode = preferences.scalingMode
        layer?.backgroundColor = preferences.backgroundColor.cgColor
        currentCanvas.backgroundColor = preferences.backgroundColor
        incomingCanvas.backgroundColor = preferences.backgroundColor
        stackCanvas.backgroundColor = preferences.backgroundColor
        resetPresentation()
        preparedImage = nil
        hasDisplayedImage = false
        isTransitioning = false
        lastAdvance = .distantPast
        titleLabel.stringValue = ""
        titleLabel.isHidden = true
        channelErrorLabel.stringValue = ""
        channelErrorLabel.isHidden = true
        statusLabel.stringValue = "Connecting to Are.na…"
        statusLabel.isHidden = false

        contentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let batch = try await ArenaAPIClient.shared.fetchContent(
                    from: preferences.channels,
                    sort: preferences.contentOrder.apiSort
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.rotationEngine.replaceContent(batch)
                    guard self.rotationEngine.hasImages else {
                        let failures = batch.failures.map {
                            "\($0.identifier): \($0.message)"
                        }
                        self.showError(
                            failures.isEmpty
                                ? "No image blocks were found in the selected channels."
                                : failures.joined(separator: "\n")
                        )
                        return
                    }
                    self.showChannelFailures(batch.failures)
                    self.statusLabel.stringValue = "Loading image…"
                    self.startRefreshLoop(using: preferences)
                    self.prepareNextImage()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func prepareNextImage() {
        guard !isSuspended, preparedImage == nil, imageTask == nil else { return }
        guard let metadata = rotationEngine.nextImage() else {
            if !hasDisplayedImage {
                showError("The image files could not be loaded. Check your connection and try again.")
            }
            return
        }

        requestMoreContentIfNeeded()
        let generation = loadGeneration
        let cacheLimitBytes = preferences.imageCacheLimitBytes
        let requiredPixels = max(bounds.width, bounds.height) * (window?.backingScaleFactor ?? 2)
        let maximumPixelSize = max(Int(requiredPixels.rounded(.up)), 1)
        let url = requiredPixels > 1_800 ? metadata.retinaURL : metadata.displayURL
        imageTask = Task { [weak self] in
            do {
                let data = try await ArenaAPIClient.shared.fetchImageData(
                    from: url,
                    maximumCacheBytes: cacheLimitBytes
                )
                guard !Task.isCancelled,
                      let decodedImage = await Self.decodeImageData(
                        data,
                        maximumPixelSize: maximumPixelSize
                      ) else {
                    throw ArenaAPIError.invalidResponse
                }
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.imageTask = nil
                    self.preparedImage = PreparedArenaImage(
                        image: NSImage(cgImage: decodedImage, size: .zero),
                        metadata: metadata
                    )
                    if !self.hasDisplayedImage ||
                        Date().timeIntervalSince(self.lastAdvance) >= self.preferences.slideDuration {
                        self.displayPreparedImage()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                let isTransient = ArenaAPIClient.isTransientFailure(error)
                if !isTransient {
                    await ArenaAPIClient.shared.invalidateCachedImage(at: url)
                }
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.imageTask = nil
                    if isTransient {
                        let message = self.networkIsAvailable
                            ? "A temporary network error interrupted image loading. Retrying shortly."
                            : "The network is unavailable. Playback will resume when it returns."
                        if self.hasDisplayedImage {
                            self.showChannelFailures([
                                ArenaChannelFailure(identifier: "Network", message: message)
                            ])
                        } else {
                            self.showError(message)
                        }
                        self.scheduleImageRetry()
                    } else {
                        self.rotationEngine.markImageFailed(id: metadata.id)
                        self.prepareNextImage()
                    }
                }
            }
        }
    }

    private static func decodeImageData(
        _ data: Data,
        maximumPixelSize: Int
    ) async -> CGImage? {
        await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }

    private func scheduleImageRetry() {
        guard imageRetryTask == nil, !isSuspended else { return }
        let generation = loadGeneration
        imageRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.loadGeneration == generation,
                      !self.isSuspended else { return }
                self.imageRetryTask = nil
                self.prepareNextImage()
            }
        }
    }

    private func displayPreparedImage() {
        guard !isTransitioning, let preparedImage else { return }
        self.preparedImage = nil
        isTransitioning = true
        transition(to: preparedImage.image, metadata: preparedImage.metadata)
        prepareNextImage()
    }

    private func requestMoreContentIfNeeded() {
        guard paginationTask == nil,
              let request = rotationEngine.nextPageRequest(),
              let channel = rotationEngine.channelContent(
                identifier: request.channelIdentifier
              ) else { return }

        let sort = preferences.contentOrder.apiSort
        paginationTask = Task { [weak self] in
            do {
                let page = try await ArenaAPIClient.shared.fetchPage(
                    after: channel,
                    page: request.page,
                    sort: sort
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.paginationTask = nil
                    self.rotationEngine.appendPage(page)
                    self.prepareNextImage()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.paginationTask = nil
                    self.rotationEngine.markPageRequestFailed(
                        channelIdentifier: request.channelIdentifier
                    )
                    self.showChannelFailures([
                        ArenaChannelFailure(
                            identifier: request.channelIdentifier,
                            message: error.localizedDescription
                        )
                    ])
                }
            }
        }
    }

    private func startRefreshLoop(using preferences: ArenaPreferences) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.refreshInterval)
                    guard !Task.isCancelled else { return }
                    let batch = try await ArenaAPIClient.shared.fetchContent(
                        from: preferences.channels,
                        sort: preferences.contentOrder.apiSort
                    )
                    guard !Task.isCancelled else { return }
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.rotationEngine.replaceContent(batch)
                        self.showChannelFailures(batch.failures)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    continue
                }
            }
        }
    }

    private func transition(to image: NSImage, metadata: ArenaImage) {
        statusLabel.isHidden = true
        let preferredTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = metadata.altText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferences.showsTitles {
            let title = preferredTitle?.isEmpty == false ? preferredTitle! : fallbackTitle ?? ""
            let attribution = [metadata.creatorName, metadata.channelTitle]
                .compactMap { value -> String? in
                    guard let value,
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return value
                }
                .joined(separator: " · ")
            titleLabel.stringValue = [title, attribution]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } else {
            titleLabel.stringValue = ""
        }
        titleLabel.isHidden = titleLabel.stringValue.isEmpty

        switch preferences.animationStyle {
        case .crossfade:
            transitionFullScreen(to: image)
        case .stack:
            addToStack(image)
        }
    }

    private func transitionFullScreen(to image: NSImage) {
        stackCanvas.isHidden = true
        incomingCanvas.image = image
        incomingCanvas.scalingMode = preferences.scalingMode
        incomingCanvas.alphaValue = 0
        incomingCanvas.isHidden = false
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? min(preferences.crossfadeDuration, 0.2)
            : preferences.crossfadeDuration

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            currentCanvas.animator().alphaValue = 0
            incomingCanvas.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            let oldCanvas = self.currentCanvas
            self.currentCanvas = self.incomingCanvas
            self.incomingCanvas = oldCanvas
            self.incomingCanvas.image = nil
            self.incomingCanvas.alphaValue = 0
            self.finishTransition()
        }
    }

    private func addToStack(_ image: NSImage) {
        stackCanvas.isHidden = false
        currentCanvas.image = nil
        incomingCanvas.image = nil
        currentCanvas.alphaValue = 1
        incomingCanvas.alphaValue = 0

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0,
              stackCanvas.bounds.width > 0, stackCanvas.bounds.height > 0 else {
            finishTransition()
            return
        }

        let maximumSize = NSSize(
            width: stackCanvas.bounds.width * 0.85,
            height: stackCanvas.bounds.height * 0.85
        )
        let fitScale = min(
            maximumSize.width / imageSize.width,
            maximumSize.height / imageSize.height,
            1
        )
        let randomScale = CGFloat.random(in: 0.45...1)
        let cardSize = NSSize(
            width: imageSize.width * fitScale * randomScale,
            height: imageSize.height * fitScale * randomScale
        )
        let availableX = max(stackCanvas.bounds.width - cardSize.width, 0)
        let availableY = max(stackCanvas.bounds.height - cardSize.height, 0)
        let overflowX = min(cardSize.width * 0.25, stackCanvas.bounds.width * 0.12)
        let overflowY = min(cardSize.height * 0.25, stackCanvas.bounds.height * 0.12)
        let destination = NSRect(
            x: CGFloat.random(in: -overflowX...(availableX + overflowX)),
            y: CGFloat.random(in: -overflowY...(availableY + overflowY)),
            width: cardSize.width,
            height: cardSize.height
        )
        stackCanvas.paint(
            image,
            in: destination,
            scale: window?.backingScaleFactor ?? 2
        )
        finishTransition()
    }

    private func resetPresentation() {
        stackCanvas.reset(scale: window?.backingScaleFactor ?? 2)
        stackCanvas.isHidden = preferences.animationStyle != .stack
        for canvas in [currentCanvas, incomingCanvas] {
            canvas.image = nil
        }
        currentCanvas.alphaValue = 1
        incomingCanvas.alphaValue = 0
    }

    private func finishTransition() {
        lastAdvance = Date()
        hasDisplayedImage = true
        isTransitioning = false
        prepareNextImage()
    }

    private func showError(_ message: String) {
        isTransitioning = false
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }

    private func showChannelFailures(_ failures: [ArenaChannelFailure]) {
        guard !failures.isEmpty else { return }
        channelErrorTask?.cancel()
        channelErrorLabel.stringValue = failures.map { failure in
            "\(failure.identifier): \(failure.message)"
        }.joined(separator: "\n")
        channelErrorLabel.isHidden = false
        let generation = loadGeneration
        channelErrorTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 12 * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.loadGeneration == generation else { return }
                self.channelErrorLabel.isHidden = true
                self.channelErrorTask = nil
            }
        }
    }
}
