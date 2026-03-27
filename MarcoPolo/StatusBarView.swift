import AppKit

final class StatusBarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var updateWorkItem: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        addSubview(label)

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 20)
    }

    func applyTheme(_ palette: EditorThemePalette) {
        layer?.backgroundColor = palette.statusBarBackground.cgColor
        label.textColor = palette.statusBarText
    }

    func updateCounts(text: String) {
        updateWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performCount(text: text)
        }
        updateWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func performCount(text: String) {
        let nsText = text as NSString
        var wordCount = 0
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            wordCount += 1
        }
        let charCount = nsText.length
        label.stringValue = "\(wordCount) words  \(charCount) characters"
    }
}
