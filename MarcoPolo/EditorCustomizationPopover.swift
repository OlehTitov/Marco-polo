import AppKit

final class EditorCustomizationViewController: NSViewController {
    var onThemeChange: ((EditorTheme) -> Void)?
    var onFontFamilyChange: ((String) -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var onContentWidthChange: ((EditorContentWidth) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "View")
    private let themeLabel = NSTextField(labelWithString: "Theme")
    private let fontLabel = NSTextField(labelWithString: "Typeface")
    private let sizeLabel = NSTextField(labelWithString: "Size")
    private let widthLabel = NSTextField(labelWithString: "Width")
    private let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontSizeSlider = NSSlider(value: 14, minValue: 11, maxValue: 28, target: nil, action: nil)
    private let fontSizeValueLabel = NSTextField(labelWithString: "")
    private let contentWidthControl = NSSegmentedControl(
        labels: EditorContentWidth.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let themeStack = NSStackView()
    private var themeButtons: [EditorTheme: ThemeSwatchButton] = [:]
    private var sectionLabels: [NSTextField] = []
    private let rootStack = NSStackView()

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        self.view = effectView
        preferredContentSize = NSSize(width: 288, height: 252)

        configureControls()
        buildLayout()
        refreshFromPreferences()
    }

    func refreshFromPreferences(_ preferences: Preferences = .shared) {
        let families = EditorFontCatalog.availableFamilies(including: preferences.fontFamily)
        fontPopup.removeAllItems()
        fontPopup.addItems(withTitles: families)

        if let index = families.firstIndex(of: preferences.fontFamily) {
            fontPopup.selectItem(at: index)
        }

        fontSizeSlider.doubleValue = Double(preferences.fontSize)
        fontSizeValueLabel.stringValue = "\(Int(preferences.fontSize.rounded())) pt"
        contentWidthControl.selectedSegment = EditorContentWidth.allCases.firstIndex(of: preferences.contentWidth) ?? 1

        for (theme, button) in themeButtons {
            button.isSelectedTheme = theme == preferences.theme
        }
    }

    func applyTheme(_ palette: EditorThemePalette, appearanceName: NSAppearance.Name?) {
        view.appearance = appearanceName.flatMap(NSAppearance.init(named:))
        titleLabel.textColor = palette.popoverLabelText
        fontSizeValueLabel.textColor = palette.popoverSecondaryText

        for label in sectionLabels {
            label.textColor = palette.popoverSecondaryText
        }
    }

    private func configureControls() {
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)

        sectionLabels = [themeLabel, fontLabel, sizeLabel, widthLabel]
        for label in sectionLabels {
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        }

        themeStack.orientation = .horizontal
        themeStack.alignment = .centerY
        themeStack.spacing = 10

        for theme in EditorTheme.allCases {
            let button = ThemeSwatchButton(theme: theme)
            button.target = self
            button.action = #selector(themeButtonPressed(_:))
            themeButtons[theme] = button
            themeStack.addArrangedSubview(button)
        }

        fontPopup.font = NSFont.systemFont(ofSize: 13)
        fontPopup.controlSize = .large
        fontPopup.target = self
        fontPopup.action = #selector(fontPopupChanged(_:))

        fontSizeSlider.numberOfTickMarks = 18
        fontSizeSlider.allowsTickMarkValuesOnly = true
        fontSizeSlider.isContinuous = true
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeSliderChanged(_:))

        fontSizeValueLabel.alignment = .right
        fontSizeValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        contentWidthControl.target = self
        contentWidthControl.action = #selector(contentWidthChanged(_:))
        contentWidthControl.segmentStyle = .rounded
        for index in 0..<contentWidthControl.segmentCount {
            contentWidthControl.setWidth(82, forSegment: index)
        }

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func buildLayout() {
        view.addSubview(rootStack)

        let sizeStack = NSStackView(views: [fontSizeSlider, fontSizeValueLabel])
        sizeStack.orientation = .horizontal
        sizeStack.spacing = 10
        fontSizeValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        rootStack.addArrangedSubview(titleLabel)
        rootStack.addArrangedSubview(makeSection(label: themeLabel, body: themeStack))
        rootStack.addArrangedSubview(makeSection(label: fontLabel, body: fontPopup))
        rootStack.addArrangedSubview(makeSection(label: sizeLabel, body: sizeStack))
        rootStack.addArrangedSubview(makeSection(label: widthLabel, body: contentWidthControl))

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func makeSection(label: NSTextField, body: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6

        body.translatesAutoresizingMaskIntoConstraints = false
        body.widthAnchor.constraint(equalToConstant: 256).isActive = true

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(body)
        return stack
    }

    @objc private func themeButtonPressed(_ sender: ThemeSwatchButton) {
        onThemeChange?(sender.theme)
    }

    @objc private func fontPopupChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        onFontFamilyChange?(title)
    }

    @objc private func fontSizeSliderChanged(_ sender: NSSlider) {
        let size = CGFloat(sender.doubleValue.rounded())
        fontSizeValueLabel.stringValue = "\(Int(size)) pt"
        onFontSizeChange?(size)
    }

    @objc private func contentWidthChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0,
              sender.selectedSegment < EditorContentWidth.allCases.count else { return }
        onContentWidthChange?(EditorContentWidth.allCases[sender.selectedSegment])
    }
}

final class ThemeSwatchButton: NSButton {
    let theme: EditorTheme
    var isSelectedTheme = false {
        didSet { needsDisplay = true }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(theme: EditorTheme) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .none
        toolTip = theme.displayName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 34, height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let appearance = theme.preferredAppearanceName.flatMap(NSAppearance.init(named:)) ?? NSApp.effectiveAppearance
        let palette = theme.palette(for: appearance)
        let preview = theme.previewColors

        let ringRect = bounds.insetBy(dx: 2, dy: 2)
        let fillRect = ringRect.insetBy(dx: isSelectedTheme ? 4 : 3, dy: isSelectedTheme ? 4 : 3)
        let ringColor = isSelectedTheme
            ? preview.accent
            : NSColor.separatorColor.withAlphaComponent(isHovered ? 0.45 : 0.2)

        ringColor.setStroke()
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = isSelectedTheme ? 2.5 : 1
        ringPath.stroke()

        preview.background.setFill()
        NSBezierPath(ovalIn: fillRect).fill()

        let accentRect = NSRect(x: fillRect.maxX - 10, y: fillRect.minY + 2, width: 8, height: 8)
        preview.accent.setFill()
        NSBezierPath(ovalIn: accentRect).fill()

        if isHovered && !isSelectedTheme {
            NSColor.separatorColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(ovalIn: fillRect).fill()
        }

        if theme == .dark || theme == .quiet {
            NSColor.separatorColor.withAlphaComponent(0.15).setStroke()
            let innerStroke = NSBezierPath(ovalIn: fillRect.insetBy(dx: 0.5, dy: 0.5))
            innerStroke.lineWidth = 1
            innerStroke.stroke()
        } else {
            let highlight = resolvedPreviewColor(palette.editorText.withAlphaComponent(0.05), for: appearance)
            highlight.setStroke()
            let innerStroke = NSBezierPath(ovalIn: fillRect.insetBy(dx: 0.5, dy: 0.5))
            innerStroke.lineWidth = 1
            innerStroke.stroke()
        }
    }
}

final class MonogramButton: NSButton {
    var palette: EditorThemePalette = EditorTheme.dark.palette(for: NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance) {
        didSet { needsDisplay = true }
    }

    var isPopoverShown = false {
        didSet { needsDisplay = true }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .none
        toolTip = "Customize editor"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 34, height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let capsuleRect = bounds.insetBy(dx: 2, dy: 2)
        let fillColor: NSColor
        if isPopoverShown {
            fillColor = palette.monogramActiveFill
        } else if isHovered {
            fillColor = palette.monogramHoverFill
        } else {
            fillColor = .clear
        }

        fillColor.setFill()
        NSBezierPath(roundedRect: capsuleRect, xRadius: 12, yRadius: 12).fill()

        let textColor = isPopoverShown ? palette.linkText : palette.monogramText
        let font = NSFont(name: "Baskerville-SemiBold", size: 15) ?? NSFont.systemFont(ofSize: 15, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let string = NSAttributedString(string: "M", attributes: attributes)
        let textSize = string.size()
        let textRect = NSRect(
            x: bounds.midX - (textSize.width / 2),
            y: bounds.midY - (textSize.height / 2) + 0.5,
            width: textSize.width,
            height: textSize.height
        )
        string.draw(in: textRect)
    }
}
