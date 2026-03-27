import AppKit

enum TextMetrics {
    static func textMargin(for font: NSFont) -> CGFloat {
        let charWidth = ("#" as NSString).size(withAttributes: [.font: font]).width
        return ceil(charWidth * 7)
    }
}

final class Preferences {
    static let shared = Preferences()
    static let didChangeNotification = Notification.Name("PreferencesDidChange")

    private enum Keys {
        static let fontFamily = "fontFamily"
        static let fontSize = "fontSize"
        static let theme = "theme"
        static let contentWidth = "contentWidth"
        static let typewriterScroll = "typewriterScroll"
    }

    var fontFamily: String {
        get { UserDefaults.standard.string(forKey: Keys.fontFamily) ?? "Menlo" }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.fontFamily)
            postChange()
        }
    }

    var fontSize: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.fontSize)
            return stored > 0 ? stored : 14
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.fontSize)
            postChange()
        }
    }

    var theme: EditorTheme {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Keys.theme),
                  let theme = EditorTheme(rawValue: rawValue) else {
                return .dark
            }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.theme)
            postChange()
        }
    }

    var contentWidth: EditorContentWidth {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Keys.contentWidth),
                  let width = EditorContentWidth(rawValue: rawValue) else {
                return .balanced
            }
            return width
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.contentWidth)
            postChange()
        }
    }

    var isTypewriterScrollEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.typewriterScroll) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.typewriterScroll)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.typewriterScroll)
            postChange()
        }
    }

    var font: NSFont {
        if let resolvedFont = EditorFontCatalog.font(for: fontFamily, size: fontSize) {
            return resolvedFont
        }

        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var boldFont: NSFont {
        let manager = NSFontManager.shared
        return manager.convert(font, toHaveTrait: .boldFontMask)
    }

    var italicFont: NSFont {
        let manager = NSFontManager.shared
        return manager.convert(font, toHaveTrait: .italicFontMask)
    }

    var boldItalicFont: NSFont {
        let manager = NSFontManager.shared
        let bold = manager.convert(font, toHaveTrait: .boldFontMask)
        return manager.convert(bold, toHaveTrait: .italicFontMask)
    }

    func themePalette(for appearance: NSAppearance? = nil) -> EditorThemePalette {
        let resolvedAppearance = appearance ?? NSApp.effectiveAppearance
        return theme.palette(for: resolvedAppearance)
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
