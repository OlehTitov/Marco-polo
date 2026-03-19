# CLAUDE.md — Marco Polo

## What This Is
A pure AppKit markdown editor for macOS. Lightweight, fast, distraction-free. For writing, not coding. Must feel instant on a 10-year-old Mac with a 50,000-line file open.

## Architecture (1924 lines total, 12 files)
- **AppDelegate.swift** — app lifecycle + full NSMenu (File, Edit, Format, View, Window)
- **Document.swift** — NSDocument, TextKit 2 stack, hosts sidebar + status bar, export, focus mode, preferences
- **EditorTextView.swift** — NSTextView subclass, typewriter scroll, auto-pair, smart newline, indent/outdent
- **FormattingCommands.swift** — extension on EditorTextView: toggle bold/italic/code/link, list continuation
- **MarkdownStyling.swift** — NSTextContentStorageDelegate, full syntax highlighting, focus mode dimming
- **MarkdownPatterns.swift** — static regex patterns, paragraph type detection, heading helpers
- **FencedCodeTracker.swift** — cross-paragraph fenced code block state tracking
- **OutlineSidebar.swift** — NSOutlineView heading tree, click-to-jump
- **StatusBarView.swift** — word/character count bar
- **MarkdownExporter.swift** — Markdown → HTML + PDF export
- **Preferences.swift** — UserDefaults wrapper (font, size, typewriter toggle)
- **main.swift** — entry point

Pure AppKit + **TextKit 2**. No SwiftUI. No Electron. No web views.

## MIGRATION: TextKit 1 → TextKit 2

The current code uses TextKit 1 (NSTextStorage + NSLayoutManager + NSTextContainer). **Migrate to TextKit 2** before adding any features. This is priority zero.

### Why
- TextKit 1 is deprecated. Apple is actively developing TextKit 2.
- TextKit 2 has lazy layout — only renders visible text. Massive RAM savings on large files.
- NSTextLayoutManager replaces NSLayoutManager with viewport-based rendering.
- NSTextContentStorage replaces NSTextStorage with better change tracking.

### How
- Replace `NSLayoutManager` → `NSTextLayoutManager`
- Replace `NSTextStorage` → `NSTextContentStorage`
- `MarkdownTextStorage` must be rewritten: instead of subclassing NSTextStorage, use `NSTextContentStorageDelegate` or `NSTextLayoutManagerDelegate` to apply styles
- `EditorTextView` stays as NSTextView subclass but configured for TextKit 2 (pass NSTextLayoutManager to init, NOT NSLayoutManager)
- Typewriter scroll logic in EditorTextView must be updated — glyph-based APIs (`glyphRange`, `boundingRect(forGlyphRange:)`) don't exist in TextKit 2. Use `NSTextLayoutManager.textLayoutFragment(for:)` and fragment frame geometry instead.
- Test: open a 50,000-line markdown file. It must scroll smoothly with <50MB RAM.

### Reference Projects (study these FIRST)

1. **STTextView** (PRIMARY) — https://github.com/krzyzanowskim/STTextView
   TextKit 2 text view built from scratch. Study their entire architecture: how they handle NSTextContentStorage, NSTextLayoutManager, viewport-based rendering, line fragment handling, gutter, and selection. This is the gold standard for TextKit 2 on macOS.

2. **SourceView** — https://github.com/ChimeHQ/SourceView
   NSTextView subclass on TextKit 2. Shows how to properly configure NSTextView in TextKit 2 mode and compose features. Closer to our approach (we subclass NSTextView, not build from scratch).

3. **MarkEdit** — https://github.com/MarkEdit-app/MarkEdit
   "TextEdit but for Markdown." Study their writing UX: keyboard shortcuts, find/replace, smart editing helpers.

4. **swift-markdown** — https://github.com/swiftlang/swift-markdown
   Apple's Markdown parser. Proper AST. Replace our hand-rolled `headingLevel(for:)` character loop with this.

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
3. **RAM is precious.** TextKit 2's viewport-based layout is your friend — only styled/laid-out text is what's on screen. Never cache the full styled document. Profile with Instruments before and after any change.
4. **Viewport-driven.** Leverage NSTextLayoutManager's lazy layout. Only process visible text + a small buffer. Never iterate the full document on keystroke.
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
0. **Migrate to TextKit 2** (NSTextContentStorage + NSTextLayoutManager). Everything else builds on this.
1. Full markdown syntax highlighting (bold, italic, code, lists, quotes, links, tasks)
2. Writing helpers (smart lists, auto-pair, formatting shortcuts)
3. Focus mode
4. Outline sidebar
5. Word count status bar
6. Export (HTML, PDF)
7. Preferences (font, font size, typewriter toggle — UserDefaults, no window needed yet)
