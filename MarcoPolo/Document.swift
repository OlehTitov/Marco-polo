import AppKit
import UniformTypeIdentifiers

final class Document: NSDocument, NSTextViewDelegate, NSWindowDelegate {
    private let markdownStyling = MarkdownStyling()
    private let textContentStorage = NSTextContentStorage()
    private var textView: EditorTextView?
    private var pendingContent: String?

    override init() {
        super.init()
        hasUndoManager = true
    }

    override class var autosavesInPlace: Bool {
        true
    }

    override class var readableTypes: [String] {
        ["net.daringfireball.markdown", UTType.plainText.identifier]
    }

    override class var writableTypes: [String] {
        ["net.daringfireball.markdown", UTType.plainText.identifier]
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.tabbingMode = .disallowed

        let contentSize = window.contentLayoutRect.size

        // TextKit 2 stack
        let textLayoutManager = NSTextLayoutManager()
        textContentStorage.delegate = markdownStyling
        textContentStorage.addTextLayoutManager(textLayoutManager)

        let container = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        textLayoutManager.textContainer = container

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentSize))
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let editor = EditorTextView(frame: scrollView.bounds, textContainer: container)
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
        editor.backgroundColor = .textBackgroundColor
        editor.insertionPointColor = .textColor
        editor.textColor = .textColor
        editor.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textContainerInset = NSSize(width: 0, height: max(140, contentSize.height * 0.35))
        editor.textContainer?.lineFragmentPadding = 0
        editor.delegate = self

        scrollView.documentView = editor

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = containerView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 72),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -72),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 0),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: 0)
        ])

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        textView = editor

        if let pending = pendingContent {
            editor.string = pending
            pendingContent = nil
        }

        editor.centerSelectionIfNeeded(animated: false)
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = textView?.string ?? textContentStorage.textStorage?.string ?? ""
        return text.data(using: .utf8) ?? Data()
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        replaceContent(with: decoded)
    }

    func textDidChange(_ notification: Notification) {
        updateChangeCount(.changeDone)
    }

    func windowDidResize(_ notification: Notification) {
        guard let textView else { return }
        let visibleHeight = textView.enclosingScrollView?.contentSize.height ?? 0
        textView.textContainerInset.height = max(140, visibleHeight * 0.35)
        textView.centerSelectionIfNeeded(animated: false)
    }

    private func replaceContent(with string: String) {
        if let textView {
            textView.string = string
        } else {
            pendingContent = string
        }
    }
}
