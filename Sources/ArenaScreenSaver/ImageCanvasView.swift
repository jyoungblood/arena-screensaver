import AppKit

final class ImageCanvasView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    var scalingMode: ImageScalingMode = .fill {
        didSet { needsDisplay = true }
    }

    var backgroundColor: NSColor = .black {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { backgroundColor.alphaComponent >= 1 }

    override func draw(_ dirtyRect: NSRect) {
        if backgroundColor.alphaComponent > 0 {
            backgroundColor.setFill()
            dirtyRect.fill()
        }

        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let destination = destinationRect(for: image.size, in: bounds, mode: scalingMode)
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func destinationRect(
        for imageSize: NSSize,
        in bounds: NSRect,
        mode: ImageScalingMode
    ) -> NSRect {
        let drawingBounds: NSRect
        if mode == .fitWithMargins {
            let margin = min(bounds.width, bounds.height) * 0.06
            drawingBounds = bounds.insetBy(dx: margin, dy: margin)
        } else {
            drawingBounds = bounds
        }

        let widthScale = drawingBounds.width / imageSize.width
        let heightScale = drawingBounds.height / imageSize.height
        let scale = mode == .fill
            ? max(widthScale, heightScale)
            : min(widthScale, heightScale)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(
            x: drawingBounds.midX - size.width / 2,
            y: drawingBounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
