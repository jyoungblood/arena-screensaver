import AppKit

final class ConfigurationWindowController: NSWindowController {
    private let channelsTextView = NSTextView()
    private let animationPopup = NSPopUpButton()
    private let scalingPopup = NSPopUpButton()
    private let orderPopup = NSPopUpButton()
    private let durationField = NSTextField()
    private let durationStepper = NSStepper()
    private let crossfadeField = NSTextField()
    private let crossfadeStepper = NSStepper()
    private let landscapeCheckbox = NSButton(
        checkboxWithTitle: "Landscape",
        target: nil,
        action: nil
    )
    private let portraitCheckbox = NSButton(
        checkboxWithTitle: "Portrait",
        target: nil,
        action: nil
    )
    private let squareCheckbox = NSButton(
        checkboxWithTitle: "Square",
        target: nil,
        action: nil
    )
    private let backgroundColorWell = NSColorWell()
    private let cacheSizePopup = NSPopUpButton()
    private let clearCacheButton = NSButton()
    private let cacheStatusLabel = NSTextField(labelWithString: "")
    private let titlesCheckbox = NSButton(
        checkboxWithTitle: "Show image titles",
        target: nil,
        action: nil
    )
    private var crossfadeRow: NSStackView?
    private var scalingRow: NSStackView?
    private let onSave: (ArenaPreferences) -> Void

    init(preferences: ArenaPreferences, onSave: @escaping (ArenaPreferences) -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Are.na Screen Saver Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface(preferences: preferences)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface(preferences: ArenaPreferences) {
        guard let contentView = window?.contentView else { return }

        let heading = NSTextField(labelWithString: "Channels")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)

        let help = NSTextField(wrappingLabelWithString:
            "Paste a full Are.na channel URL, slug, or numeric ID. Add one channel per line, up to 10 channels."
        )
        help.textColor = .secondaryLabelColor

        channelsTextView.string = preferences.channels.joined(separator: "\n")
        channelsTextView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        channelsTextView.isRichText = false
        channelsTextView.isAutomaticQuoteSubstitutionEnabled = false
        channelsTextView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = channelsTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 112).isActive = true

        animationPopup.addItems(withTitles: AnimationStyle.allCases.map(\.title))
        animationPopup.selectItem(
            at: AnimationStyle.allCases.firstIndex(of: preferences.animationStyle) ?? 0
        )
        animationPopup.target = self
        animationPopup.action = #selector(animationChanged)
        let animationRow = makeRow(title: "Animation", control: animationPopup)

        configureNumberInput(
            field: durationField,
            stepper: durationStepper,
            value: preferences.slideDuration,
            minimum: 1,
            maximum: 120,
            increment: 1,
            decimalPlaces: 0,
            fieldAction: #selector(durationFieldChanged),
            stepperAction: #selector(durationStepperChanged)
        )
        let durationRow = makeRow(
            title: "Change every",
            control: makeNumberControl(field: durationField, stepper: durationStepper)
        )

        configureNumberInput(
            field: crossfadeField,
            stepper: crossfadeStepper,
            value: preferences.crossfadeDuration,
            minimum: 0.2,
            maximum: 3,
            increment: 0.1,
            decimalPlaces: 1,
            fieldAction: #selector(crossfadeFieldChanged),
            stepperAction: #selector(crossfadeStepperChanged)
        )
        let crossfadeRow = makeRow(
            title: "Crossfade duration",
            control: makeNumberControl(field: crossfadeField, stepper: crossfadeStepper)
        )
        self.crossfadeRow = crossfadeRow

        scalingPopup.addItems(withTitles: ImageScalingMode.allCases.map(\.title))
        scalingPopup.selectItem(
            at: ImageScalingMode.allCases.firstIndex(of: preferences.scalingMode) ?? 0
        )
        let scalingRow = makeRow(title: "Image sizing", control: scalingPopup)
        self.scalingRow = scalingRow

        orderPopup.addItems(withTitles: ContentOrder.allCases.map(\.title))
        orderPopup.selectItem(
            at: ContentOrder.allCases.firstIndex(of: preferences.contentOrder) ?? 0
        )
        let orderRow = makeRow(title: "Order", control: orderPopup)

        let orientationSelection: [(NSButton, ImageOrientationFilter)] = [
            (landscapeCheckbox, .landscape),
            (portraitCheckbox, .portrait),
            (squareCheckbox, .square)
        ]
        for (checkbox, orientation) in orientationSelection {
            checkbox.state = preferences.orientationFilter.contains(orientation) ? .on : .off
            checkbox.target = self
            checkbox.action = #selector(orientationChanged(_:))
        }
        let orientationControls = NSStackView(views: orientationSelection.map(\.0))
        orientationControls.orientation = .horizontal
        orientationControls.spacing = 12
        let orientationRow = makeRow(title: "Orientations", control: orientationControls)

        backgroundColorWell.color = preferences.backgroundColor
        backgroundColorWell.translatesAutoresizingMaskIntoConstraints = false
        backgroundColorWell.widthAnchor.constraint(equalToConstant: 72).isActive = true
        backgroundColorWell.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let backgroundRow = makeRow(title: "Background", control: backgroundColorWell)

        cacheSizePopup.addItems(
            withTitles: ArenaPreferences.imageCacheSizeOptions.map(Self.cacheSizeTitle)
        )
        cacheSizePopup.selectItem(
            at: ArenaPreferences.imageCacheSizeOptions.firstIndex(
                of: preferences.imageCacheSizeMB
            ) ?? 2
        )
        clearCacheButton.title = "Clear Cache"
        clearCacheButton.bezelStyle = .rounded
        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCacheClicked)
        cacheStatusLabel.textColor = .secondaryLabelColor
        cacheStatusLabel.lineBreakMode = .byTruncatingTail
        let cacheControls = NSStackView(views: [
            cacheSizePopup,
            clearCacheButton,
            cacheStatusLabel
        ])
        cacheControls.orientation = .horizontal
        cacheControls.alignment = .centerY
        cacheControls.spacing = 8
        let cacheRow = makeRow(title: "Image cache", control: cacheControls)

        titlesCheckbox.state = preferences.showsTitles ? .on : .off
        let options = NSStackView(views: [titlesCheckbox])
        options.orientation = .vertical
        options.alignment = .leading
        options.spacing = 8

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [
            heading,
            help,
            scrollView,
            animationRow,
            crossfadeRow,
            durationRow,
            scalingRow,
            orderRow,
            orientationRow,
            backgroundRow,
            cacheRow,
            options,
            NSView(),
            buttons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        for row in [
            animationRow,
            crossfadeRow,
            scalingRow,
            durationRow,
            orderRow,
            orientationRow,
            backgroundRow,
            cacheRow,
            buttons
        ] {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
        updateContextualOptions()
        updateCacheUsage()
    }

    private func makeRow(title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 145).isActive = true
        let row = NSStackView(views: [label, control, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeNumberControl(field: NSTextField, stepper: NSStepper) -> NSStackView {
        let suffix = NSTextField(labelWithString: "seconds")
        let control = NSStackView(views: [field, stepper, suffix])
        control.orientation = .horizontal
        control.alignment = .centerY
        control.spacing = 6
        return control
    }

    private func configureNumberInput(
        field: NSTextField,
        stepper: NSStepper,
        value: Double,
        minimum: Double,
        maximum: Double,
        increment: Double,
        decimalPlaces: Int,
        fieldAction: Selector,
        stepperAction: Selector
    ) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximum = NSNumber(value: maximum)
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        formatter.allowsFloats = decimalPlaces > 0

        field.formatter = formatter
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.doubleValue = value
        field.target = self
        field.action = fieldAction
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 58).isActive = true

        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = increment
        stepper.doubleValue = value
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.target = self
        stepper.action = stepperAction
    }

    @objc private func durationFieldChanged() {
        synchronize(field: durationField, stepper: durationStepper, decimalPlaces: 0)
    }

    @objc private func durationStepperChanged() {
        durationField.doubleValue = durationStepper.doubleValue
    }

    @objc private func crossfadeFieldChanged() {
        synchronize(field: crossfadeField, stepper: crossfadeStepper, decimalPlaces: 1)
    }

    @objc private func crossfadeStepperChanged() {
        crossfadeField.doubleValue = crossfadeStepper.doubleValue
    }

    private func synchronize(
        field: NSTextField,
        stepper: NSStepper,
        decimalPlaces: Int
    ) {
        let factor = pow(10, Double(decimalPlaces))
        let clamped = min(max(field.doubleValue, stepper.minValue), stepper.maxValue)
        let value = (clamped * factor).rounded() / factor
        field.doubleValue = value
        stepper.doubleValue = value
    }

    @objc private func animationChanged() {
        updateContextualOptions()
    }

    @objc private func orientationChanged(_ sender: NSButton) {
        guard selectedOrientations().isEmpty else { return }
        sender.state = .on
        NSSound.beep()
    }

    private func updateContextualOptions() {
        let index = max(animationPopup.indexOfSelectedItem, 0)
        let usesCrossfade = AnimationStyle.allCases[index] == .crossfade
        crossfadeRow?.isHidden = !usesCrossfade
        scalingRow?.isHidden = !usesCrossfade
    }

    private func selectedOrientations() -> ImageOrientationFilter {
        var selection: ImageOrientationFilter = []
        if landscapeCheckbox.state == .on { selection.insert(.landscape) }
        if portraitCheckbox.state == .on { selection.insert(.portrait) }
        if squareCheckbox.state == .on { selection.insert(.square) }
        return selection
    }

    private static func cacheSizeTitle(_ megabytes: Int) -> String {
        megabytes >= 1_024
            ? "\(megabytes / 1_024) GB"
            : "\(megabytes) MB"
    }

    private func updateCacheUsage() {
        cacheStatusLabel.stringValue = "Calculating…"
        Task { [weak self] in
            let size = (try? await ArenaAPIClient.shared.imageCacheSize()) ?? 0
            await MainActor.run { [weak self] in
                self?.cacheStatusLabel.stringValue = ByteCountFormatter.string(
                    fromByteCount: size,
                    countStyle: .file
                ) + " used"
            }
        }
    }

    @objc private func clearCacheClicked() {
        clearCacheButton.isEnabled = false
        cacheStatusLabel.stringValue = "Clearing…"
        Task { [weak self] in
            do {
                try await ArenaAPIClient.shared.clearCaches()
                await MainActor.run { [weak self] in
                    self?.cacheStatusLabel.stringValue = "Cache cleared"
                    self?.clearCacheButton.isEnabled = true
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.cacheStatusLabel.stringValue = "Could not clear cache"
                    self?.clearCacheButton.isEnabled = true
                }
            }
        }
    }

    @objc private func cancelClicked() {
        guard let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .cancel)
    }

    @objc private func saveClicked() {
        window?.makeFirstResponder(nil)
        synchronize(field: durationField, stepper: durationStepper, decimalPlaces: 0)
        synchronize(field: crossfadeField, stepper: crossfadeStepper, decimalPlaces: 1)

        let channels = ArenaPreferences.parseChannels(channelsTextView.string)
        let animationIndex = max(animationPopup.indexOfSelectedItem, 0)
        let modeIndex = max(scalingPopup.indexOfSelectedItem, 0)
        let orderIndex = max(orderPopup.indexOfSelectedItem, 0)
        let cacheSizeIndex = max(cacheSizePopup.indexOfSelectedItem, 0)
        let preferences = ArenaPreferences(
            channels: channels.isEmpty ? [ArenaPreferences.defaultChannel] : channels,
            slideDuration: durationField.doubleValue,
            crossfadeDuration: crossfadeField.doubleValue,
            animationStyle: AnimationStyle.allCases[animationIndex],
            scalingMode: ImageScalingMode.allCases[modeIndex],
            contentOrder: ContentOrder.allCases[orderIndex],
            orientationFilter: selectedOrientations(),
            backgroundColor: backgroundColorWell.color,
            imageCacheSizeMB: ArenaPreferences.imageCacheSizeOptions[cacheSizeIndex],
            showsTitles: titlesCheckbox.state == .on
        )
        preferences.save()
        Task {
            try? await ArenaAPIClient.shared.trimImageCache(
                to: preferences.imageCacheLimitBytes
            )
        }
        onSave(preferences)
        guard let window else { return }
        window.sheetParent?.endSheet(window, returnCode: .OK)
    }
}
