import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        buildMenuBar()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Marco Polo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Marco Polo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Marco Polo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        let exportHTML = fileMenu.addItem(withTitle: "Export HTML…", action: #selector(Document.exportHTML(_:)), keyEquivalent: "E")
        exportHTML.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Export PDF…", action: #selector(Document.exportPDF(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        let findReplace = editMenu.addItem(withTitle: "Find and Replace…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findReplace.keyEquivalentModifierMask = [.command, .option]
        findReplace.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Format menu
        let formatMenu = NSMenu(title: "Format")
        let boldItem = formatMenu.addItem(withTitle: "Bold", action: #selector(EditorTextView.toggleBold(_:)), keyEquivalent: "b")
        _ = boldItem
        let italicItem = formatMenu.addItem(withTitle: "Italic", action: #selector(EditorTextView.toggleItalic(_:)), keyEquivalent: "i")
        _ = italicItem
        let codeItem = formatMenu.addItem(withTitle: "Code", action: #selector(EditorTextView.toggleInlineCode(_:)), keyEquivalent: "C")
        codeItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(withTitle: "Link", action: #selector(EditorTextView.insertMarkdownLink(_:)), keyEquivalent: "k")
        formatMenu.addItem(.separator())
        formatMenu.addItem(withTitle: "Increase Font Size", action: #selector(Document.increaseFontSize(_:)), keyEquivalent: "=")
        formatMenu.addItem(withTitle: "Decrease Font Size", action: #selector(Document.decreaseFontSize(_:)), keyEquivalent: "-")
        let formatMenuItem = NSMenuItem()
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let focusItem = viewMenu.addItem(withTitle: "Focus Mode", action: #selector(Document.toggleFocusMode(_:)), keyEquivalent: "F")
        focusItem.keyEquivalentModifierMask = [.command, .shift]
        let outlineItem = viewMenu.addItem(withTitle: "Outline", action: #selector(Document.toggleOutlineSidebar(_:)), keyEquivalent: "O")
        outlineItem.keyEquivalentModifierMask = [.command, .shift]
        let wordCountItem = viewMenu.addItem(withTitle: "Word Count", action: #selector(Document.toggleStatusBar(_:)), keyEquivalent: "W")
        wordCountItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Typewriter Scroll", action: #selector(Document.toggleTypewriterScroll(_:)), keyEquivalent: "")
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
