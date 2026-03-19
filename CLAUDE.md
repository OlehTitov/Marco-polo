# CLAUDE.md — Marco Polo

## What This Is
A pure AppKit markdown editor for macOS. Lightweight, fast, distraction-free. For writing, not coding. Must feel instant on a 10-year-old Mac with a 50,000-line file open.

## Architecture (288 lines total)
- **MarkdownTextStorage** — NSTextStorage subclass, paragraph-level styling
- **EditorTextView** — NSTextView subclass, typewriter scroll (cursor stays centered)
- **Document** — NSDocument, NSLayoutManager + NSTextContainer, autosave, plain text I/O
- **AppDelegate** — app lifecycle
- **main.swift** — entry point

Pure AppKit + TextKit 1. No SwiftUI. No Electron. No web views.

## Reference Projects

Clone and study before making changes:

1. **MarkEdit** — https://github.com/MarkEdit-app/MarkEdit
   "TextEdit but for Markdown." Closest to Marco Polo's vision. Study their keyboard shortcuts, find/replace, smart editing helpers.

2. **STTextView** — https://github.com/krzyzanowskim/STTextView
   TextKit 2 text view component. Study their incremental styling and performance patterns. Consider as future engine replacement if TextKit 1 becomes a bottleneck.

3. **SourceView** — https://github.com/ChimeHQ/SourceView
   NSTextView + TextKit 2 subclass from the Chime team. Study text container handling and composable feature design.

4. **swift-markdown** — https://github.com/swiftlang/swift-markdown
   Apple's Markdown parser. Proper AST. Consider replacing our hand-rolled heading detection with this.

## What Needs Work

### Syntax Highlighting (currently headings only)
Add styling for:
- **Bold** / *Italic* / ~~Strikethrough~~
- `Inline code`
- Block quotes (> prefix)
- Fenced code blocks (``` delimiters — style the whole block, no language-specific coloring needed)
- Lists (ordered + unordered, nested indentation)
- Links `[text](url)` — style the text portion, dim the URL
- Horizontal rules
- Task lists `- [ ]` / `- [x]`

All highlighting must be incremental — only re-style the edited paragraph, never the whole document.

### Writing Helpers
- Smart list continuation (Enter after `- item` → inserts `- `, Enter after `1. item` → inserts `2. `)
- Smart indent (Tab/Shift-Tab to indent/outdent list items and code blocks)
- Auto-pair: `**`, `` ` ``, `(`, `[`, `"` — wrap selected text when pair character is typed
- Toggle formatting shortcuts: Cmd+B bold, Cmd+I italic, Cmd+K link, Cmd+Shift+C code
- Smart quotes and dashes OFF by default (it's markdown, not Word)

### Navigation
- Outline sidebar (Cmd+Shift+O toggle) — heading tree, click to jump. Lightweight NSOutlineView, not a panel.
- Focus mode (Cmd+Shift+F) — dim all paragraphs except the one with the cursor. Just opacity on non-active paragraphs.
- Quick open (Cmd+P) — if multiple documents open, switch between them

### Editor Polish
- Word count + character count in a minimal status bar (bottom edge, tiny, optional Cmd+Shift+W toggle)
- Configurable font and font size (Cmd+Plus/Minus to resize, stored in UserDefaults)
- Remember window position and size between sessions
- Full-screen support (native macOS, no custom implementation)
- Export to HTML and PDF (Cmd+Shift+E menu)
- Proper menu bar (File, Edit, Format, View)

## Coding Rules

1. **Pure AppKit.** No SwiftUI, no web views, no Catalyst. System frameworks only.
2. **No third-party dependencies** unless critical. `swift-markdown` from Apple is acceptable. Nothing from CocoaPods/Carthage.
3. **RAM is precious.** No caching entire styled documents in memory. Style on demand, discard when offscreen. Profile with Instruments before and after any change.
4. **Incremental everything.** Syntax highlighting, layout, scrolling — only process what's visible or just changed. Never iterate the full document on every keystroke.
5. **NSDocument architecture.** All file I/O through the document model. Autosave in place.
6. **Typewriter scroll is sacred.** Cursor centering is a core feature. Toggleable via menu, on by default.
7. **Dark mode via semantic colors.** Use `.textColor`, `.textBackgroundColor`, `.secondaryLabelColor`, etc. Never hardcode RGB values. Light and dark mode work automatically.
8. **Keyboard-first.** Every action gets a shortcut. Mouse is secondary.
9. **One file, one concern.** Split at ~300 lines.
10. **No images, no themes, no line numbers.** This is a writing tool, not an IDE.

## Build & Run
- Xcode project: `MarcoPolo.xcodeproj`
- Target: macOS (AppKit)
- No package dependencies yet
- Open in Xcode → Cmd+R

## Priority Order
1. Full markdown syntax highlighting (bold, italic, code, lists, quotes, links, tasks)
2. Writing helpers (smart lists, auto-pair, formatting shortcuts)
3. Focus mode
4. Outline sidebar
5. Word count status bar
6. Export (HTML, PDF)
7. Preferences (font, font size, typewriter toggle — UserDefaults, no window needed yet)
