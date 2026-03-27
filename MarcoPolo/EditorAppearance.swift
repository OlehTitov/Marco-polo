import AppKit

enum EditorContentWidth: String, CaseIterable {
    case narrow
    case balanced
    case wide

    var title: String {
        switch self {
        case .narrow: return "Narrow"
        case .balanced: return "Balanced"
        case .wide: return "Wide"
        }
    }

    var maxWidth: CGFloat {
        switch self {
        case .narrow: return 560
        case .balanced: return 700
        case .wide: return 860
        }
    }
}

struct EditorThemePalette {
    let editorBackground: NSColor
    let editorText: NSColor
    let secondaryText: NSColor
    let tertiaryText: NSColor
    let subduedText: NSColor
    let linkText: NSColor
    let caret: NSColor
    let sidebarBackground: NSColor
    let sidebarText: NSColor
    let sidebarBorder: NSColor
    let statusBarBackground: NSColor
    let statusBarText: NSColor
    let separator: NSColor
    let codeBlockFill: NSColor
    let inlineCodeFill: NSColor
    let inlineCodeText: NSColor
    let fadeOverlayColor: NSColor
    let fadeOverlayOpacity: CGFloat
    let monogramText: NSColor
    let monogramHoverFill: NSColor
    let monogramActiveFill: NSColor
    let popoverLabelText: NSColor
    let popoverSecondaryText: NSColor
    let codeThemeName: String
}

enum EditorTheme: String, CaseIterable {
    case system
    case paper
    case mist
    case midnight

    var displayName: String {
        switch self {
        case .system: return "System"
        case .paper: return "Paper"
        case .mist: return "Mist"
        case .midnight: return "Midnight"
        }
    }

    var preferredAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .paper, .mist:
            return .aqua
        case .midnight:
            return .darkAqua
        }
    }

    func palette(for appearance: NSAppearance) -> EditorThemePalette {
        switch self {
        case .system:
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return EditorThemePalette(
                editorBackground: .textBackgroundColor,
                editorText: .textColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                subduedText: .tertiaryLabelColor,
                linkText: .linkColor,
                caret: .systemBlue,
                sidebarBackground: .windowBackgroundColor,
                sidebarText: .labelColor,
                sidebarBorder: .separatorColor.withAlphaComponent(isDark ? 0.75 : 0.45),
                statusBarBackground: .windowBackgroundColor,
                statusBarText: .secondaryLabelColor,
                separator: .separatorColor,
                codeBlockFill: .labelColor.withAlphaComponent(isDark ? 0.06 : 0.035),
                inlineCodeFill: .labelColor.withAlphaComponent(isDark ? 0.11 : 0.07),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .textBackgroundColor,
                fadeOverlayOpacity: isDark ? 1.0 : 0.98,
                monogramText: .tertiaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(isDark ? 0.18 : 0.10),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(isDark ? 0.34 : 0.18),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor,
                codeThemeName: isDark ? "atom-one-dark" : "atom-one-light"
            )

        case .paper:
            return EditorThemePalette(
                editorBackground: .underPageBackgroundColor,
                editorText: .labelColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                subduedText: .tertiaryLabelColor,
                linkText: .linkColor,
                caret: .controlAccentColor,
                sidebarBackground: .controlBackgroundColor,
                sidebarText: .labelColor,
                sidebarBorder: .separatorColor.withAlphaComponent(0.4),
                statusBarBackground: .windowBackgroundColor,
                statusBarText: .secondaryLabelColor,
                separator: .separatorColor,
                codeBlockFill: .labelColor.withAlphaComponent(0.035),
                inlineCodeFill: .labelColor.withAlphaComponent(0.06),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .underPageBackgroundColor,
                fadeOverlayOpacity: 0.97,
                monogramText: .secondaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(0.12),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(0.16),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor,
                codeThemeName: "atom-one-light"
            )

        case .mist:
            return EditorThemePalette(
                editorBackground: .windowBackgroundColor,
                editorText: .labelColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                subduedText: .tertiaryLabelColor,
                linkText: .controlAccentColor,
                caret: .controlAccentColor,
                sidebarBackground: .controlBackgroundColor,
                sidebarText: .labelColor,
                sidebarBorder: .separatorColor.withAlphaComponent(0.42),
                statusBarBackground: .controlBackgroundColor,
                statusBarText: .secondaryLabelColor,
                separator: .separatorColor,
                codeBlockFill: .labelColor.withAlphaComponent(0.03),
                inlineCodeFill: .labelColor.withAlphaComponent(0.055),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .windowBackgroundColor,
                fadeOverlayOpacity: 0.96,
                monogramText: .secondaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(0.13),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(0.18),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor,
                codeThemeName: "atom-one-light"
            )

        case .midnight:
            return EditorThemePalette(
                editorBackground: .textBackgroundColor,
                editorText: .textColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                subduedText: .tertiaryLabelColor,
                linkText: .systemBlue,
                caret: .systemBlue,
                sidebarBackground: .windowBackgroundColor,
                sidebarText: .labelColor,
                sidebarBorder: .separatorColor.withAlphaComponent(0.78),
                statusBarBackground: .windowBackgroundColor,
                statusBarText: .secondaryLabelColor,
                separator: .separatorColor,
                codeBlockFill: .labelColor.withAlphaComponent(0.07),
                inlineCodeFill: .labelColor.withAlphaComponent(0.12),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .textBackgroundColor,
                fadeOverlayOpacity: 1.0,
                monogramText: .secondaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(0.2),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(0.38),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor,
                codeThemeName: "atom-one-dark"
            )
        }
    }

    var previewColors: (background: NSColor, accent: NSColor) {
        let appearance = preferredAppearanceName.flatMap(NSAppearance.init(named:)) ?? NSApp.effectiveAppearance
        let palette = self.palette(for: appearance)
        let accent = palette.monogramActiveFill.blended(withFraction: 0.35, of: palette.linkText) ?? palette.linkText
        return (palette.editorBackground, accent)
    }
}

enum EditorFontCatalog {
    private static let curatedFamilies = [
        "Iowan Old Style",
        "Baskerville",
        "Georgia",
        "Avenir Next",
        "Helvetica Neue",
        "Palatino",
        "Martian Mono",
        "Geist Mono",
        "Geist Pixel",
        "IBM Plex Mono",
        "Lekton",
        "Brass Mono",
        "Typewalk 1915 Thin-Demo",
        "Menlo"
    ]

    private static let preferredMemberKeywords: [String: [String]] = [
        "typewalk1915": ["thin"]
    ]

    static func availableFamilies(including currentFamily: String? = nil) -> [String] {
        let installedFamilies = NSFontManager.shared.availableFontFamilies
        var families: [String] = []

        for family in curatedFamilies {
            if let resolved = resolvedInstalledFamily(for: family, installedFamilies: installedFamilies),
               !families.contains(resolved) {
                families.append(resolved)
            }
        }

        if let currentFamily,
           let resolved = resolvedInstalledFamily(for: currentFamily, installedFamilies: installedFamilies),
           !families.contains(resolved) {
            families.insert(resolved, at: 0)
        }

        if families.isEmpty {
            return Array(installedFamilies.sorted().prefix(12))
        }

        return families
    }

    static func resolvedInstalledFamily(for requestedName: String, installedFamilies: [String]? = nil) -> String? {
        let installedFamilies = installedFamilies ?? NSFontManager.shared.availableFontFamilies

        if installedFamilies.contains(requestedName) {
            return requestedName
        }

        let normalizedRequested = normalize(requestedName)

        if let exactNormalizedMatch = installedFamilies.first(where: { normalize($0) == normalizedRequested }) {
            return exactNormalizedMatch
        }

        if let looseMatch = installedFamilies.first(where: {
            let normalizedInstalled = normalize($0)
            return normalizedInstalled.contains(normalizedRequested) || normalizedRequested.contains(normalizedInstalled)
        }) {
            return looseMatch
        }

        return nil
    }

    static func font(for requestedName: String, size: CGFloat) -> NSFont? {
        if let namedFont = NSFont(name: requestedName, size: size) {
            return namedFont
        }

        guard let resolvedFamily = resolvedInstalledFamily(for: requestedName) else {
            return nil
        }

        if let preferredMember = preferredMember(for: resolvedFamily, requestedName: requestedName),
           let preferredFont = NSFont(name: preferredMember.postScriptName, size: size) {
            return preferredFont
        }

        return NSFontManager.shared.font(withFamily: resolvedFamily, traits: [], weight: 5, size: size)
    }

    private static func preferredMember(for family: String, requestedName: String) -> FontMember? {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            return nil
        }

        let keywords = preferredKeywords(for: requestedName, family: family)
        guard !keywords.isEmpty else { return nil }

        let parsedMembers = members.compactMap(FontMember.init)

        return parsedMembers.first(where: { member in
            keywords.allSatisfy { keyword in
                member.normalizedStyle.contains(keyword) || member.normalizedPostScript.contains(keyword)
            }
        })
    }

    private static func preferredKeywords(for requestedName: String, family: String) -> [String] {
        let normalizedRequested = normalize(requestedName)
        let normalizedFamily = normalize(family)

        for (familyKey, keywords) in preferredMemberKeywords {
            if normalizedRequested.contains(familyKey) || normalizedFamily.contains(familyKey) {
                return keywords
            }
        }

        return []
    }

    private static func normalize(_ name: String) -> String {
        name
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private struct FontMember {
        let postScriptName: String
        let normalizedPostScript: String
        let normalizedStyle: String

        init?(_ rawMember: [Any]) {
            guard rawMember.count >= 2,
                  let postScriptName = rawMember[0] as? String,
                  let styleName = rawMember[1] as? String else {
                return nil
            }

            self.postScriptName = postScriptName
            self.normalizedPostScript = normalize(postScriptName)
            self.normalizedStyle = normalize(styleName)
        }
    }
}
