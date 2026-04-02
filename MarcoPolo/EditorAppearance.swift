import AppKit

private extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

func resolvedPreviewColor(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
    var resolved = color
    if #available(macOS 11.0, *) {
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
    } else {
        resolved = color.usingColorSpace(.deviceRGB) ?? color
    }
    return resolved
}

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

enum EditorCaretColorOption: String, CaseIterable {
    case theme
    case orange
    case purple
    case turquoise
    case green
    case pink

    var displayName: String {
        switch self {
        case .theme: return "Theme"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .turquoise: return "Turquoise"
        case .green: return "Green"
        case .pink: return "Pink"
        }
    }

    func resolvedColor(themePalette: EditorThemePalette, appearance: NSAppearance) -> NSColor {
        let color: NSColor
        switch self {
        case .theme:
            color = themePalette.caret
        case .orange:
            color = .systemOrange
        case .purple:
            color = .systemPurple
        case .turquoise:
            color = .systemTeal
        case .green:
            color = .systemGreen
        case .pink:
            color = .systemPink
        }

        return resolvedPreviewColor(color, for: appearance)
    }
}

struct EditorThemePalette {
    let editorBackground: NSColor
    let editorText: NSColor
    let selectionFill: NSColor
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
    let inlineCodeText: NSColor
    let fadeOverlayColor: NSColor
    let fadeOverlayOpacity: CGFloat
    let monogramText: NSColor
    let monogramHoverFill: NSColor
    let monogramActiveFill: NSColor
    let popoverLabelText: NSColor
    let popoverSecondaryText: NSColor
}

enum EditorTheme: String, CaseIterable {
    case light
    case paper
    case dark
    case calm
    case quiet

    var displayName: String {
        switch self {
        case .light: return "Light"
        case .paper: return "Paper"
        case .dark: return "Dark"
        case .calm: return "Calm"
        case .quiet: return "Quiet"
        }
    }

    var preferredAppearanceName: NSAppearance.Name? {
        switch self {
        case .light, .paper, .calm:
            return .aqua
        case .dark, .quiet:
            return .darkAqua
        }
    }

    func palette(for appearance: NSAppearance) -> EditorThemePalette {
        switch self {
        case .light:
            return EditorThemePalette(
                editorBackground: .textBackgroundColor,
                editorText: .labelColor,
                selectionFill: .selectedContentBackgroundColor.withAlphaComponent(0.26),
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                subduedText: .tertiaryLabelColor,
                linkText: .controlAccentColor,
                caret: .controlAccentColor,
                sidebarBackground: .windowBackgroundColor,
                sidebarText: .labelColor,
                sidebarBorder: .separatorColor.withAlphaComponent(0.45),
                statusBarBackground: .windowBackgroundColor,
                statusBarText: .secondaryLabelColor,
                separator: .separatorColor,
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .textBackgroundColor,
                fadeOverlayOpacity: 0.98,
                monogramText: .secondaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(0.10),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(0.18),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor
            )

        case .paper:
            let latteBase = NSColor.hex(0xEFF1F5)
            let latteMantle = NSColor.hex(0xE6E9EF)
            let latteCrust = NSColor.hex(0xDCE0E8)
            let latteText = NSColor.hex(0x4C4F69)
            let latteSubtext1 = NSColor.hex(0x5C5F77)
            let latteSubtext0 = NSColor.hex(0x6C6F85)
            let latteSurface0 = NSColor.hex(0xCCD0DA)
            let latteBlue = NSColor.hex(0x1E66F5)
            let latteSapphire = NSColor.hex(0x209FB5)

            return EditorThemePalette(
                editorBackground: latteBase,
                editorText: latteText,
                selectionFill: latteBlue.withAlphaComponent(0.18),
                secondaryText: latteSubtext1,
                tertiaryText: latteSubtext0,
                subduedText: latteSubtext0.withAlphaComponent(0.76),
                linkText: latteSapphire,
                caret: latteBlue,
                sidebarBackground: latteMantle,
                sidebarText: latteText,
                sidebarBorder: latteSurface0.withAlphaComponent(0.68),
                statusBarBackground: latteMantle,
                statusBarText: latteSubtext1,
                separator: latteCrust.withAlphaComponent(0.9),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: latteBase,
                fadeOverlayOpacity: 1.0,
                monogramText: latteSubtext1,
                monogramHoverFill: latteSurface0.withAlphaComponent(0.34),
                monogramActiveFill: latteBlue.withAlphaComponent(0.18),
                popoverLabelText: latteText,
                popoverSecondaryText: latteSubtext1
            )

        case .dark:
            return EditorThemePalette(
                editorBackground: .textBackgroundColor,
                editorText: .textColor,
                selectionFill: .selectedContentBackgroundColor.withAlphaComponent(0.28),
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
                inlineCodeText: .systemOrange,
                fadeOverlayColor: .textBackgroundColor,
                fadeOverlayOpacity: 1.0,
                monogramText: .secondaryLabelColor,
                monogramHoverFill: .separatorColor.withAlphaComponent(0.2),
                monogramActiveFill: .selectedContentBackgroundColor.withAlphaComponent(0.38),
                popoverLabelText: .labelColor,
                popoverSecondaryText: .secondaryLabelColor
            )

        case .calm:
            let parchment = NSColor.hex(0xF1E9D2)
            let cafeNoir = NSColor.hex(0x4B3621)
            let darkSepia = NSColor.hex(0x604830)
            let sepia = NSColor.hex(0x80613C)
            let paperBrown = NSColor.hex(0xB18C65)
            let sepiaInk = NSColor.hex(0x74421C)
            let sidebarBackground = parchment.blended(withFraction: 0.08, of: paperBrown) ?? parchment
            let statusBarBackground = parchment.blended(withFraction: 0.12, of: paperBrown) ?? parchment

            return EditorThemePalette(
                editorBackground: parchment,
                editorText: cafeNoir,
                selectionFill: paperBrown.withAlphaComponent(0.22),
                secondaryText: darkSepia,
                tertiaryText: sepia,
                subduedText: sepia.withAlphaComponent(0.78),
                linkText: sepiaInk,
                caret: sepiaInk,
                sidebarBackground: sidebarBackground,
                sidebarText: cafeNoir,
                sidebarBorder: paperBrown.withAlphaComponent(0.42),
                statusBarBackground: statusBarBackground,
                statusBarText: darkSepia,
                separator: paperBrown.withAlphaComponent(0.34),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: parchment,
                fadeOverlayOpacity: 1.0,
                monogramText: darkSepia.withAlphaComponent(0.9),
                monogramHoverFill: paperBrown.withAlphaComponent(0.14),
                monogramActiveFill: paperBrown.withAlphaComponent(0.26),
                popoverLabelText: cafeNoir,
                popoverSecondaryText: darkSepia
            )

        case .quiet:
            let nord1 = NSColor.hex(0x3B4252)
            let nord2 = NSColor.hex(0x434C5E)
            let nord3 = NSColor.hex(0x4C566A)
            let nord4 = NSColor.hex(0xD8DEE9)
            let nord5 = NSColor.hex(0xE5E9F0)
            let nord8 = NSColor.hex(0x88C0D0)
            let nord9 = NSColor.hex(0x81A1C1)

            return EditorThemePalette(
                editorBackground: nord2,
                editorText: nord4,
                selectionFill: nord8.withAlphaComponent(0.24),
                secondaryText: nord4.withAlphaComponent(0.84),
                tertiaryText: nord4.withAlphaComponent(0.66),
                subduedText: nord4.withAlphaComponent(0.52),
                linkText: nord8,
                caret: nord5,
                sidebarBackground: nord1,
                sidebarText: nord4,
                sidebarBorder: nord3.withAlphaComponent(0.62),
                statusBarBackground: nord1,
                statusBarText: nord4.withAlphaComponent(0.78),
                separator: nord3.withAlphaComponent(0.56),
                inlineCodeText: .systemOrange,
                fadeOverlayColor: nord2,
                fadeOverlayOpacity: 1.0,
                monogramText: nord4.withAlphaComponent(0.86),
                monogramHoverFill: nord3.withAlphaComponent(0.34),
                monogramActiveFill: nord9.withAlphaComponent(0.34),
                popoverLabelText: nord5,
                popoverSecondaryText: nord4.withAlphaComponent(0.78)
            )
        }
    }

    var previewColors: (background: NSColor, accent: NSColor) {
        let appearance = preferredAppearanceName.flatMap(NSAppearance.init(named:)) ?? NSApp.effectiveAppearance
        let palette = self.palette(for: appearance)
        let accent = palette.monogramActiveFill.blended(withFraction: 0.35, of: palette.linkText) ?? palette.linkText
        return (
            resolvedPreviewColor(palette.editorBackground, for: appearance),
            resolvedPreviewColor(accent, for: appearance)
        )
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
