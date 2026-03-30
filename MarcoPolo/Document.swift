import AppKit
import UniformTypeIdentifiers

private func resolvedCGColor(_ color: NSColor, with appearance: NSAppearance) -> CGColor {
    var resolvedColor = color.cgColor
    if #available(macOS 11.0, *) {
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
    }
    return resolvedColor
}

final class Document: NSDocument, NSTextViewDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let markdownStyling = MarkdownStyling()
    private let fencedCodeTracker = FencedCodeTracker()
    private let textContentStorage = NSTextContentStorage()
    private var textView: EditorTextView?
    private var pendingContent: String?

    // UI components
    private var scrollView: NSScrollView?
    private var outlineSidebar: OutlineSidebar?
    private var statusBarView: StatusBarView?
    private var containerView: NSView?
    private var topFadeView: EdgeFadeView?
    private var bottomFadeView: EdgeFadeView?
    private var customizationButton: MonogramButton?
    private var customizationPopover: NSPopover?
    private var customizationController: EditorCustomizationViewController?

    // Layout constraints for toggling
    private var scrollViewBottomConstraint: NSLayoutConstraint?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var statusBarHeightConstraint: NSLayoutConstraint?

    // State
    var isFocusModeEnabled: Bool { markdownStyling.isFocusModeEnabled }
    private var isSidebarVisible = false
    private var isStatusBarVisible = false
    private var selectionObserver: NSObjectProtocol?
    private var prefsObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?

    override init() {
        super.init()
        hasUndoManager = true
        markdownStyling.fencedCodeTracker = fencedCodeTracker
    }

    deinit {
        if let obs = selectionObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = prefsObserver { NotificationCenter.default.removeObserver(obs) }
    }

    override class var autosavesInPlace: Bool { true }

    override class var readableTypes: [String] {
        ["net.daringfireball.markdown", UTType.plainText.identifier]
    }

    override class var writableTypes: [String] {
        ["net.daringfireball.markdown", UTType.plainText.identifier]
    }

    // MARK: - Window setup

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("DocumentWindow")

        let contentSize = window.contentLayoutRect.size

        // TextKit 2 stack
        let textLayoutManager = NSTextLayoutManager()
        textLayoutManager.usesFontLeading = false
        textLayoutManager.delegate = markdownStyling
        textContentStorage.delegate = markdownStyling
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let container = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        textLayoutManager.textContainer = container

        // Scroll view
        let sv = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.borderType = .noBorder
        sv.drawsBackground = true
        sv.backgroundColor = .textBackgroundColor
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        scrollView = sv

        // Editor
        let prefs = Preferences.shared
        let editor = EditorTextView(frame: sv.bounds, textContainer: container)
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.usesFindBar = true
        editor.allowsUndo = true
        editor.minSize = NSSize(width: 0, height: contentSize.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.drawsBackground = false
        editor.backgroundColor = .textBackgroundColor
        editor.setCaretColor(.systemBlue)
        editor.textColor = .textColor
        editor.font = prefs.font
        editor.textContainerInset = NSSize(width: 80, height: max(140, contentSize.height * 0.35)) // width updated in updateTextInsets
        editor.textContainer?.lineFragmentPadding = 0
        editor.delegate = self
        sv.documentView = editor

        // Container view
        let cv = NSView()
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.wantsLayer = true
        window.contentView = cv
        containerView = cv

        // Outline sidebar
        let sidebar = OutlineSidebar(frame: .zero)
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.isHidden = true
        sidebar.onSelectHeading = { [weak self] location in
            self?.jumpToLocation(location)
        }
        outlineSidebar = sidebar
        cv.addSubview(sidebar)

        // Status bar
        let statusBar = StatusBarView(frame: .zero)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.isHidden = true
        statusBarView = statusBar
        cv.addSubview(statusBar)

        cv.addSubview(sv)

        // Edge fade overlays (above scroll view in z-order)
        let fadeHeight: CGFloat = 112
        let topFade = EdgeFadeView(edge: .top)
        topFade.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(topFade)
        topFadeView = topFade

        let bottomFade = EdgeFadeView(edge: .bottom)
        bottomFade.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bottomFade)
        bottomFadeView = bottomFade

        let customization = MonogramButton(frame: .zero)
        customization.translatesAutoresizingMaskIntoConstraints = false
        customization.target = self
        customization.action = #selector(toggleCustomizationPopover(_:))
        cv.addSubview(customization)
        customizationButton = customization

        let customizationVC = EditorCustomizationViewController()
        customizationVC.onThemeChange = { theme in
            Preferences.shared.theme = theme
        }
        customizationVC.onCaretColorChange = { option in
            Preferences.shared.caretColorOption = option
        }
        customizationVC.onFontFamilyChange = { family in
            Preferences.shared.fontFamily = family
        }
        customizationVC.onFontSizeChange = { size in
            Preferences.shared.fontSize = size
        }
        customizationVC.onContentWidthChange = { width in
            Preferences.shared.contentWidth = width
        }
        customizationController = customizationVC

        let customizationPopover = NSPopover()
        customizationPopover.animates = true
        customizationPopover.behavior = .transient
        customizationPopover.delegate = self
        customizationPopover.contentViewController = customizationVC
        self.customizationPopover = customizationPopover

        // Constraints
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 0)
        sidebarWidthConstraint = sidebarWidth

        let statusHeight = statusBar.heightAnchor.constraint(equalToConstant: 0)
        statusBarHeightConstraint = statusHeight

        let scrollBottom = sv.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
        scrollViewBottomConstraint = scrollBottom

        NSLayoutConstraint.activate([
            // Sidebar
            sidebar.topAnchor.constraint(equalTo: cv.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sidebarWidth,

            // Scroll view — leading follows sidebar, fills to trailing
            sv.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sv.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            sv.topAnchor.constraint(equalTo: cv.topAnchor),
            scrollBottom,

            // Status bar
            statusBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            statusHeight,

            // Top fade — pinned to scroll view top edge
            topFade.topAnchor.constraint(equalTo: sv.topAnchor),
            topFade.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            topFade.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            topFade.heightAnchor.constraint(equalToConstant: fadeHeight),

            // Bottom fade — pinned to scroll view bottom edge
            bottomFade.bottomAnchor.constraint(equalTo: sv.bottomAnchor),
            bottomFade.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            bottomFade.heightAnchor.constraint(equalToConstant: fadeHeight),

            // Left-edge customization trigger
            customization.leadingAnchor.constraint(equalTo: sv.leadingAnchor, constant: 12),
            customization.centerYAnchor.constraint(equalTo: sv.centerYAnchor)
        ])

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        textView = editor
        editor.fencedCodeTracker = fencedCodeTracker

        if let pending = pendingContent {
            editor.string = pending
            pendingContent = nil
        }

        // Initial state
        rebuildFenceTracker()
        editor.syncTypingAttributes()
        outlineSidebar?.rebuildOutline(from: editor.string)
        if isStatusBarVisible {
            statusBarView?.updateCounts(text: editor.string)
        }

        updateTextInsets()
        applyPreferences()
        editor.centerSelectionIfNeeded(animated: false)


        // Observe selection changes for focus mode
        selectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EditorSelectionDidChange"),
            object: editor,
            queue: .main
        ) { [weak self] _ in
            self?.handleSelectionChange()
        }

        // Observe preferences changes
        prefsObserver = NotificationCenter.default.addObserver(
            forName: Preferences.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPreferences()
        }

        // Observe appearance changes for code highlight theme switching
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self else { return }
            self.applyPreferences()
        }
    }

    // MARK: - File I/O

    override func data(ofType typeName: String) throws -> Data {
        let text = textView?.string ?? textContentStorage.textStorage?.string ?? ""
        return text.data(using: .utf8) ?? Data()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        replaceContent(with: decoded)
    }

    // MARK: - Text delegate

    func textDidChange(_ notification: Notification) {
        updateChangeCount(.changeDone)
        rebuildFenceTracker()
        markdownStyling.clearHighlightCache()
        textView?.syncTypingAttributes()
        if isSidebarVisible, let text = textView?.string {
            outlineSidebar?.scheduleRebuild(from: text)
        }
        if isStatusBarVisible, let text = textView?.string {
            statusBarView?.updateCounts(text: text)
        }
    }

    // MARK: - Window delegate

    func windowDidResize(_ notification: Notification) {
        guard let textView else { return }
        let visibleHeight = textView.enclosingScrollView?.contentSize.height ?? 0
        textView.textContainerInset.height = max(140, visibleHeight * 0.35)
        updateTextInsets()
        if Preferences.shared.isTypewriterScrollEnabled {
            textView.centerSelectionIfNeeded(animated: false)
        }
    }

    private func updateTextInsets() {
        guard let textView, let scrollView else { return }
        let availableWidth = scrollView.contentSize.width
        let minInset: CGFloat = 48
        let desiredWidth = min(Preferences.shared.contentWidth.maxWidth, max(200, availableWidth - 2 * minInset))
        let inset = max(minInset, (availableWidth - desiredWidth) / 2)
        textView.textContainerInset.width = inset
        textView.textContainer?.size.width = max(200, availableWidth - 2 * inset)
    }

    // MARK: - Focus mode

    @objc func toggleFocusMode(_ sender: Any?) {
        markdownStyling.isFocusModeEnabled.toggle()
        if markdownStyling.isFocusModeEnabled {
            handleSelectionChange()
        } else {
            markdownStyling.focusedParagraphLocation = nil
        }
        invalidateAllParagraphs()
    }

    private func handleSelectionChange() {
        guard markdownStyling.isFocusModeEnabled, let textView, let ts = textContentStorage.textStorage else { return }
        let sel = textView.selectedRange()
        let str = ts.string as NSString
        guard sel.location <= str.length else { return }
        let paraRange = str.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let newLoc = paraRange.location
        if newLoc != markdownStyling.focusedParagraphLocation {
            markdownStyling.focusedParagraphLocation = newLoc
            invalidateAllParagraphs()
        }
    }

    // MARK: - Outline sidebar

    @objc func toggleOutlineSidebar(_ sender: Any?) {
        isSidebarVisible.toggle()

        if isSidebarVisible {
            outlineSidebar?.isHidden = false
            if let text = textView?.string {
                outlineSidebar?.rebuildOutline(from: text)
            }
        }

        sidebarWidthConstraint?.constant = isSidebarVisible ? 220 : 0

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            containerView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if !self.isSidebarVisible {
                self.outlineSidebar?.isHidden = true
            }
        })
    }

    // MARK: - Status bar

    @objc func toggleStatusBar(_ sender: Any?) {
        isStatusBarVisible.toggle()

        if isStatusBarVisible {
            statusBarView?.isHidden = false
            if let text = textView?.string {
                statusBarView?.updateCounts(text: text)
            }
        }

        statusBarHeightConstraint?.constant = isStatusBarVisible ? 20 : 0

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            containerView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if !self.isStatusBarVisible {
                self.statusBarView?.isHidden = true
            }
        })
    }

    // MARK: - Typewriter scroll toggle

    @objc func toggleTypewriterScroll(_ sender: Any?) {
        Preferences.shared.isTypewriterScrollEnabled.toggle()
    }

    @objc func toggleCustomizationPopover(_ sender: Any?) {
        guard let customizationButton, let customizationPopover else { return }

        if customizationPopover.isShown {
            customizationPopover.performClose(sender)
            return
        }

        customizationController?.refreshFromPreferences()
        customizationButton.isPopoverShown = true
        customizationPopover.show(relativeTo: customizationButton.bounds, of: customizationButton, preferredEdge: .maxX)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleTypewriterScroll(_:)) {
            menuItem.state = Preferences.shared.isTypewriterScrollEnabled ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleFocusMode(_:)) {
            menuItem.state = markdownStyling.isFocusModeEnabled ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleOutlineSidebar(_:)) {
            menuItem.state = isSidebarVisible ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleStatusBar(_:)) {
            menuItem.state = isStatusBarVisible ? .on : .off
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    // MARK: - Font size

    @objc func increaseFontSize(_ sender: Any?) {
        let prefs = Preferences.shared
        prefs.fontSize = min(prefs.fontSize + 1, 48)
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        let prefs = Preferences.shared
        prefs.fontSize = max(prefs.fontSize - 1, 8)
    }

    // MARK: - Export

    @objc func exportHTML(_ sender: Any?) {
        guard let text = textView?.string else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.html]
        panel.nameFieldStringValue = (displayName ?? "Untitled") + ".html"
        panel.beginSheetModal(for: windowControllers.first!.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            let html = MarkdownExporter.toHTML(text)
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let text = textView?.string else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = (displayName ?? "Untitled") + ".pdf"
        panel.beginSheetModal(for: windowControllers.first!.window!) { response in
            guard response == .OK, let url = panel.url else { return }
            if let data = MarkdownExporter.toPDF(text) {
                try? data.write(to: url)
            }
        }
    }

    // MARK: - Preferences changes

    private func applyPreferences() {
        guard let textView else { return }
        let prefs = Preferences.shared
        let window = windowControllers.first?.window

        window?.appearance = prefs.theme.preferredAppearanceName.flatMap(NSAppearance.init(named:))
        let appearance = window?.effectiveAppearance ?? textView.effectiveAppearance
        let palette = prefs.themePalette(for: appearance)

        markdownStyling.currentAppearance = appearance
        markdownStyling.updateThemeIfNeeded()
        textView.font = prefs.font
        textView.backgroundColor = palette.editorBackground
        textView.setCaretColor(prefs.caretColor(for: appearance))
        textView.textColor = palette.editorText
        textView.applyTheme(palette)
        scrollView?.backgroundColor = palette.editorBackground
        containerView?.layer?.backgroundColor = resolvedCGColor(palette.editorBackground, with: appearance)
        window?.backgroundColor = palette.editorBackground
        outlineSidebar?.applyTheme(palette)
        statusBarView?.applyTheme(palette)
        topFadeView?.applyTheme(palette)
        bottomFadeView?.applyTheme(palette)
        customizationButton?.palette = palette
        customizationController?.applyTheme(palette, appearanceName: prefs.theme.preferredAppearanceName)
        customizationController?.refreshFromPreferences(prefs)
        updateTextInsets()
        textView.syncTypingAttributes()
        textView.needsDisplay = true
        invalidateAllParagraphs()
    }

    // MARK: - Helpers

    private func replaceContent(with string: String) {
        if let textView {
            textView.string = string
            rebuildFenceTracker()
            outlineSidebar?.rebuildOutline(from: string)
        } else {
            pendingContent = string
        }
    }

    private func rebuildFenceTracker() {
        guard let ts = textContentStorage.textStorage else { return }
        fencedCodeTracker.rebuild(from: ts)
    }

    private func invalidateAllParagraphs() {
        guard let ts = textContentStorage.textStorage else { return }
        textContentStorage.performEditingTransaction {
            ts.edited(.editedAttributes, range: NSRange(location: 0, length: ts.length), changeInLength: 0)
        }
    }

    private func jumpToLocation(_ location: Int) {
        guard let textView else { return }
        let range = NSRange(location: min(location, (textView.string as NSString).length), length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        if Preferences.shared.isTypewriterScrollEnabled {
            textView.centerSelectionIfNeeded(animated: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        customizationButton?.isPopoverShown = false
    }
}

// MARK: - Edge fade overlay

private final class EdgeFadeView: NSView {
    enum Edge { case top, bottom }

    private let edge: Edge
    private let fillLayer = CALayer()
    private let maskLayer = CAGradientLayer()
    private var currentPalette: EditorThemePalette?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(fillLayer)
        fillLayer.mask = maskLayer
        maskLayer.type = .axial
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = bounds
        maskLayer.frame = bounds
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        fillLayer.contentsScale = scale
        maskLayer.contentsScale = scale
        CATransaction.commit()
        updateGradient()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // click-through
    }

    func applyTheme(_ palette: EditorThemePalette) {
        currentPalette = palette
        updateGradient()
    }

    private func updateGradient() {
        guard let currentPalette, bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        fillLayer.backgroundColor = resolvedCGColor(currentPalette.fadeOverlayColor, with: appearance)
        let stops = Self.gradientStops(maxOpacity: currentPalette.fadeOverlayOpacity)
        maskLayer.colors = stops.colors
        maskLayer.locations = stops.locations
        switch edge {
        case .top:
            maskLayer.startPoint = CGPoint(x: 0.5, y: 1)
            maskLayer.endPoint = CGPoint(x: 0.5, y: 0)
        case .bottom:
            maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
        }
        CATransaction.commit()
    }

    private static func gradientStops(maxOpacity: CGFloat) -> (colors: [CGColor], locations: [NSNumber]) {
        let sampleCount = 14
        var colors: [CGColor] = []
        var locations: [NSNumber] = []

        for index in 0..<sampleCount {
            let t = CGFloat(index) / CGFloat(sampleCount - 1)
            let smooth = t * t * (3 - (2 * t))
            let alpha = pow(1 - smooth, 1.35) * maxOpacity
            colors.append(NSColor.white.withAlphaComponent(alpha).cgColor)
            locations.append(NSNumber(value: Double(t)))
        }

        return (colors, locations)
    }
}
