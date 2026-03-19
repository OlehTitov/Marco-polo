import AppKit

// MARK: - Heading model

final class HeadingItem: NSObject {
    let title: String
    let level: Int
    let location: Int
    var children: [HeadingItem] = []

    init(title: String, level: Int, location: Int) {
        self.title = title
        self.level = level
        self.location = location
    }
}

// MARK: - Outline sidebar view

final class OutlineSidebar: NSView {
    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private var rootItems: [HeadingItem] = []
    var onSelectHeading: ((Int) -> Void)?

    private var rebuildWorkItem: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.title = "Outline"
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 16
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.target = self
        outlineView.action = #selector(outlineViewClicked(_:))

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    // MARK: - Rebuild outline

    func rebuildOutline(from text: String) {
        rootItems.removeAll()

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var allHeadings: [HeadingItem] = []

        nsText.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring else { return }
            let level = MarkdownPatterns.headingLevel(for: substring)
            if level > 0 {
                let title = String(substring.dropFirst(level + 1)) // drop "## "
                let item = HeadingItem(title: title, level: level, location: substringRange.location)
                allHeadings.append(item)
            }
        }

        // Build tree: headings nest under the nearest preceding higher-level heading
        rootItems = buildTree(from: allHeadings)
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func scheduleRebuild(from text: String) {
        rebuildWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.rebuildOutline(from: text)
        }
        rebuildWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func buildTree(from headings: [HeadingItem]) -> [HeadingItem] {
        var roots: [HeadingItem] = []
        var stack: [HeadingItem] = []

        for heading in headings {
            // Pop stack until we find a parent with lower level
            while let last = stack.last, last.level >= heading.level {
                stack.removeLast()
            }

            if let parent = stack.last {
                parent.children.append(heading)
            } else {
                roots.append(heading)
            }
            stack.append(heading)
        }

        return roots
    }

    @objc private func outlineViewClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? HeadingItem else { return }
        onSelectHeading?(item.location)
    }
}

// MARK: - NSOutlineViewDataSource

extension OutlineSidebar: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let heading = item as? HeadingItem {
            return heading.children.count
        }
        return rootItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let heading = item as? HeadingItem {
            return heading.children[index]
        }
        return rootItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let heading = item as? HeadingItem {
            return !heading.children.isEmpty
        }
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension OutlineSidebar: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let heading = item as? HeadingItem else { return nil }

        let cellID = NSUserInterfaceItemIdentifier("HeadingCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.identifier = cellID
        }

        cell.textField?.stringValue = heading.title
        let fontSize: CGFloat = heading.level <= 2 ? 13 : 11
        let weight: NSFont.Weight = heading.level <= 2 ? .semibold : .regular
        cell.textField?.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        cell.textField?.textColor = .labelColor

        return cell
    }
}
